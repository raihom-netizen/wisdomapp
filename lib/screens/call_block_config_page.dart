import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/call_block_numbers.dart';
import '../services/call_block_service.dart';
import '../theme/theme_context.dart';
import '../widgets/modern_module_ui.dart';
import 'call_block_relatorio_page.dart' show callBlockFormatarNumero;

/// «Bloqueio de chamadas — meu aparelho» (SOMENTE ANDROID): permitir
/// contatos salvos, bloquear × silenciar, números permitidos e bloqueados
/// (digitados à mão). O «Salvar neste aparelho» fica fixo no rodapé, acima
/// da barra de navegação do Android.
class CallBlockConfigPage extends StatefulWidget {
  const CallBlockConfigPage({super.key});

  static Future<void> abrir(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => const CallBlockConfigPage()),
      );

  @override
  State<CallBlockConfigPage> createState() => _CallBlockConfigPageState();
}

const _vermelho = [Color(0xFFEF4444), Color(0xFFF97316)];
const _verde = [Color(0xFF10B981), Color(0xFF34D399)];
const _roxo = [Color(0xFF7C3AED), Color(0xFFA855F7)];
const _azul = [Color(0xFF2563EB), Color(0xFF38BDF8)];

class _CallBlockConfigPageState extends State<CallBlockConfigPage> {
  CallBlockConfig _cfg = const CallBlockConfig();
  CallBlockConfig _salvo = const CallBlockConfig();
  bool _carregando = true;
  bool _salvando = false;
  final _permitidoCtrl = TextEditingController();
  final _bloqueadoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    CallBlockService.config().then((c) {
      if (!mounted) return;
      setState(() {
        _cfg = c;
        _salvo = c;
        _carregando = false;
      });
    });
  }

  @override
  void dispose() {
    _permitidoCtrl.dispose();
    _bloqueadoCtrl.dispose();
    super.dispose();
  }

  bool get _mudou =>
      _cfg.permitirContatos != _salvo.permitirContatos ||
      _cfg.silenciar != _salvo.silenciar ||
      _cfg.permitidos.join('|') != _salvo.permitidos.join('|') ||
      _cfg.bloqueados.join('|') != _salvo.bloqueados.join('|');

  static String _digitos(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// Mesma regra do nativo (DDD + 8 finais; 9º dígito e +55 não atrapalham).
  static bool _mesmo(String a, String b) => callBlockMesmoNumero(a, b);

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  void _adicionar({required bool permitido}) {
    final ctrl = permitido ? _permitidoCtrl : _bloqueadoCtrl;
    final n = ctrl.text.trim();
    if (_digitos(n).length < 8) {
      _snack('Digite o número com DDD (ex.: 62 99999-9999).');
      return;
    }
    final lista = permitido ? _cfg.permitidos : _cfg.bloqueados;
    if (lista.any((e) => _mesmo(e, n))) {
      _snack('Esse número já está na lista.');
      return;
    }
    setState(() {
      // Um número não fica nas duas listas ao mesmo tempo.
      if (permitido) {
        _cfg = _cfg.copyWith(
          permitidos: [..._cfg.permitidos, n],
          bloqueados: _cfg.bloqueados.where((e) => !_mesmo(e, n)).toList(),
        );
      } else {
        _cfg = _cfg.copyWith(
          bloqueados: [..._cfg.bloqueados, n],
          permitidos: _cfg.permitidos.where((e) => !_mesmo(e, n)).toList(),
        );
      }
      ctrl.clear();
    });
  }

  void _remover(String n, {required bool permitido}) => setState(() {
        _cfg = permitido
            ? _cfg.copyWith(permitidos: _cfg.permitidos.where((e) => e != n).toList())
            : _cfg.copyWith(bloqueados: _cfg.bloqueados.where((e) => e != n).toList());
      });

  Future<void> _salvar() async {
    // Número digitado e esquecido sem tocar no «+» também entra.
    if (_digitos(_permitidoCtrl.text).length >= 8) _adicionar(permitido: true);
    if (_digitos(_bloqueadoCtrl.text).length >= 8) _adicionar(permitido: false);
    setState(() => _salvando = true);
    final c = await CallBlockService.salvarConfig(_cfg);
    if (!mounted) return;
    setState(() {
      _cfg = c;
      _salvo = c;
      _salvando = false;
    });
    _snack('Salvo neste aparelho.');
  }

  @override
  Widget build(BuildContext context) {
    final fundoInferior = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: context.appScaffold,
      appBar: AppBar(
        foregroundColor: Colors.white,
        title: const Text('Bloqueio de chamadas', style: TextStyle(fontWeight: FontWeight.w900)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: _vermelho, begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
        ),
      ),
      // Rodapé fixo: o «Salvar» nunca fica escondido atrás da barra do Android.
      bottomNavigationBar: _carregando
          ? null
          : Container(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + fundoInferior),
              decoration: BoxDecoration(
                color: context.appScaffold,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, -3))],
              ),
              child: SizedBox(
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: _mudou ? _verde : [Colors.grey.shade500, Colors.grey.shade400]),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _salvando ? null : _salvar,
                    icon: _salvando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_rounded),
                    label: Text(_mudou ? 'Salvar neste aparelho' : 'Tudo salvo',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5)),
                  ),
                ),
              ),
            ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _cardInfo(),
                const SizedBox(height: 12),
                _cardSwitch(
                  grad: _verde,
                  icone: Icons.contact_phone_rounded,
                  titulo: 'Permitir contatos salvos',
                  texto: 'Números salvos na sua agenda sempre podem ligar.',
                  valor: _cfg.permitirContatos,
                  onChanged: (v) => setState(() => _cfg = _cfg.copyWith(permitirContatos: v)),
                ),
                const SizedBox(height: 12),
                _cardAcao(),
                const SizedBox(height: 12),
                _cardLista(
                  grad: _azul,
                  icone: Icons.playlist_add_check_rounded,
                  titulo: 'Números permitidos',
                  texto: 'Sempre podem ligar, mesmo sem estar nos contatos.',
                  ctrl: _permitidoCtrl,
                  lista: _cfg.permitidos,
                  permitido: true,
                ),
                const SizedBox(height: 12),
                _cardLista(
                  grad: _vermelho,
                  icone: Icons.block_rounded,
                  titulo: 'Números bloqueados',
                  texto: 'Sempre caem, mesmo que estejam nos contatos.',
                  ctrl: _bloqueadoCtrl,
                  lista: _cfg.bloqueados,
                  permitido: false,
                ),
              ],
            ),
    );
  }

  BoxDecoration _deco(List<Color> grad, {bool forte = false}) => BoxDecoration(
        gradient: LinearGradient(
          colors: [grad.first.withValues(alpha: forte ? 0.16 : 0.08), ModernModuleUI.cardBg(context)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: grad.first.withValues(alpha: 0.35)),
        boxShadow: [BoxShadow(color: grad.first.withValues(alpha: 0.10), blurRadius: 14, offset: const Offset(0, 6))],
      );

  Widget _icone(List<Color> grad, IconData i) => Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: grad.first.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Icon(i, color: Colors.white),
      );

  Widget _titulo(String t, String s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: context.appTextPrimary)),
        const SizedBox(height: 2),
        Text(s, style: TextStyle(fontSize: 12.5, height: 1.3, color: context.appTextSecondary, fontWeight: FontWeight.w600)),
      ]);

  Widget _cardInfo() => Container(
        padding: const EdgeInsets.all(14),
        decoration: _deco(const [Color(0xFF0EA5E9), Color(0xFF22D3EE)]),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _icone(const [Color(0xFF0EA5E9), Color(0xFF22D3EE)], Icons.verified_user_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: _titulo(
              'Vale só para este celular',
              'Bloqueia ligações de números não salvos ou não permitidos. O app nunca lê o conteúdo '
                  'das chamadas ou mensagens — só o número de quem liga.',
            ),
          ),
        ]),
      );

  Widget _cardSwitch({
    required List<Color> grad,
    required IconData icone,
    required String titulo,
    required String texto,
    required bool valor,
    required ValueChanged<bool> onChanged,
  }) =>
      Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
        decoration: _deco(grad, forte: valor),
        child: Row(children: [
          _icone(grad, icone),
          const SizedBox(width: 12),
          Expanded(child: _titulo(titulo, texto)),
          Switch(value: valor, activeThumbColor: grad.first, onChanged: onChanged),
        ]),
      );

  Widget _cardAcao() {
    Widget opcao(String t, IconData i, bool sel, List<Color> grad, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: sel ? LinearGradient(colors: grad) : null,
                color: sel ? null : grad.first.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: sel ? Colors.transparent : grad.first.withValues(alpha: 0.30)),
                boxShadow: sel ? [BoxShadow(color: grad.first.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))] : null,
              ),
              child: Column(children: [
                Icon(i, color: sel ? Colors.white : grad.first),
                const SizedBox(height: 6),
                Text(t, style: TextStyle(fontWeight: FontWeight.w900, color: sel ? Colors.white : context.appTextPrimary)),
              ]),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _deco(_roxo),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _icone(_roxo, Icons.tune_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: _titulo(
              'O que fazer com a chamada',
              _cfg.silenciar
                  ? 'Silenciar: a ligação entra sem tocar e fica no histórico.'
                  : 'Bloquear: a ligação é recusada (como ocupado).',
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          opcao('Bloquear', Icons.call_end_rounded, !_cfg.silenciar, _vermelho,
              () => setState(() => _cfg = _cfg.copyWith(silenciar: false))),
          const SizedBox(width: 10),
          opcao('Silenciar', Icons.notifications_off_rounded, _cfg.silenciar, _roxo,
              () => setState(() => _cfg = _cfg.copyWith(silenciar: true))),
        ]),
      ]),
    );
  }

  Widget _cardLista({
    required List<Color> grad,
    required IconData icone,
    required String titulo,
    required String texto,
    required TextEditingController ctrl,
    required List<String> lista,
    required bool permitido,
  }) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: _deco(grad),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            _icone(grad, icone),
            const SizedBox(width: 12),
            Expanded(child: _titulo('$titulo (${lista.length})', texto)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9()+\- ]'))],
                onSubmitted: (_) => _adicionar(permitido: permitido),
                decoration: InputDecoration(
                  hintText: '(62) 99999-9999',
                  prefixIcon: Icon(Icons.phone_rounded, color: grad.first),
                  filled: true,
                  fillColor: context.appInputFill,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 52,
              width: 56,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: grad),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: IconButton(
                  tooltip: permitido ? 'Adicionar aos permitidos' : 'Adicionar aos bloqueados',
                  onPressed: () => _adicionar(permitido: permitido),
                  icon: const Icon(Icons.add_rounded, color: Colors.white),
                ),
              ),
            ),
          ]),
          if (lista.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final n in lista)
                  Chip(
                    avatar: Icon(permitido ? Icons.check_circle_rounded : Icons.block_rounded, size: 18, color: grad.first),
                    label: Text(callBlockFormatarNumero(n), style: const TextStyle(fontWeight: FontWeight.w800)),
                    backgroundColor: grad.first.withValues(alpha: 0.10),
                    side: BorderSide(color: grad.first.withValues(alpha: 0.35)),
                    onDeleted: () => _remover(n, permitido: permitido),
                  ),
              ],
            ),
          ],
        ]),
      );
}
