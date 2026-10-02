import 'package:flutter/material.dart';

import '../screens/call_block_config_page.dart';
import '../screens/call_block_relatorio_page.dart';
import '../services/call_block_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_context.dart';
import 'modern_module_ui.dart';

/// Configurações → «Bloquear chamadas de desconhecidos» (SOMENTE ANDROID).
///
/// Recusa ligações de números que não estão nos contatos do aparelho usando o
/// papel de triagem de chamadas do Android 10+. Fora do Android devolve um
/// widget vazio (o card não aparece).
class CallBlockSettingsCard extends StatefulWidget {
  const CallBlockSettingsCard({super.key});

  @override
  State<CallBlockSettingsCard> createState() => _CallBlockSettingsCardState();
}

class _CallBlockSettingsCardState extends State<CallBlockSettingsCard>
    with WidgetsBindingObserver {
  CallBlockStatus _st = const CallBlockStatus(platformSupported: true);
  bool _loading = true;
  bool _busy = false;

  /// Histórico das recusadas (para o resumo Hoje/Mês/Ano do card).
  List<CallBlockRegistro> _registros = const [];

  static const _gradOn = [Color(0xFFEF4444), Color(0xFFF97316)];
  static const _gradOff = [Color(0xFF64748B), Color(0xFF94A3B8)];

  @override
  void initState() {
    super.initState();
    if (!CallBlockService.platformSupported) return;
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    if (CallBlockService.platformSupported) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  /// Volta das configurações do aparelho → reconsulta (permissão pode ter mudado).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = await CallBlockService.status();
    final r = await CallBlockService.registros();
    if (!mounted) return;
    setState(() {
      _st = s;
      _registros = r;
      _loading = false;
    });
  }

  Future<void> _abrirRelatorio() async {
    await CallBlockRelatorioPage.abrir(context);
    if (mounted) _refresh();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Prévia moderna (bottom sheet) antes de pedir as autorizações. É o aviso
  /// que o Google Play exige antes de pedir acesso aos contatos; um toque em
  /// «Ativar agora» já pede tudo em sequência e liga o bloqueio sozinho.
  Future<bool> _explicar() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PreviaBloqueioSheet(
        contatosOk: _st.contactsGranted,
        papelOk: _st.roleHeld,
      ),
    );
    return ok == true;
  }

  Future<void> _contatosNegados() async {
    final abrir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Acesso aos contatos negado'),
        content: const Text(
          'Sem acesso aos contatos o app não consegue saber quem está salvo, '
          'então o bloqueio não pode ser ligado. Libere «Contatos» nas '
          'permissões do app e tente de novo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Agora não'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Abrir configurações'),
          ),
        ],
      ),
    );
    if (abrir == true) await CallBlockService.openAppSettings();
  }

  /// Pede o que falta (contatos + papel de triagem). True se ficou tudo ok.
  Future<bool> _garantirPermissoes() async {
    var s = await CallBlockService.status();
    if (!s.contactsGranted) {
      final ok = await CallBlockService.requestContactsPermission();
      if (!ok) {
        if (mounted) await _contatosNegados();
        return false;
      }
    }
    s = await CallBlockService.status();
    if (!s.roleHeld) {
      final ok = await CallBlockService.requestRole();
      if (!ok) {
        _snack(
          'Para bloquear, escolha o WISDOMAPP como app de identificação '
          'de chamadas e spam.',
        );
        return false;
      }
    }
    return true;
  }

  Future<void> _onToggle(bool v) async {
    if (_busy) return;
    if (v && !_st.roleAvailable) {
      _naoSuportado();
      return;
    }
    setState(() => _busy = true);
    try {
      if (!v) {
        final s = await CallBlockService.setEnabled(false);
        if (!mounted) return;
        setState(() => _st = s);
        _snack('Bloqueio de chamadas desligado.');
        return;
      }
      // Autorizações já dadas: liga direto, sem perguntar nada. Faltando
      // alguma: prévia moderna → «Ativar agora» pede tudo e liga sozinho.
      final atual = await CallBlockService.status();
      final tudoOk = atual.contactsGranted && atual.roleHeld;
      if (!tudoOk && !await _explicar()) return;
      if (!tudoOk && !await _garantirPermissoes()) {
        await _refresh();
        return;
      }
      final s = await CallBlockService.setEnabled(true);
      if (!mounted) return;
      setState(() => _st = s);
      _snack(
        s.active
            ? 'Pronto! Ligações de números fora dos contatos serão recusadas.'
            : 'Ligado, mas ainda falta permissão para funcionar.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _concederPendente() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _garantirPermissoes();
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _naoSuportado() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Não disponível neste aparelho'),
        content: Text(
          _st.sdkInt > 0 && _st.sdkInt < 29
              ? 'O bloqueio de chamadas precisa do Android 10 ou mais novo. '
                  'Este aparelho está numa versão anterior, que não permite a '
                  'outro app filtrar ligações.'
              : 'Este aparelho não oferece a opção de app de identificação de '
                  'chamadas e spam, necessária para o bloqueio.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  /// «Limpar»: mesma prévia do relatório; apaga os registros e zera.
  Future<void> _zerarContador() async {
    if (!await confirmarLimparRegistrosBloqueio(context, _registros.length)) return;
    final s = await CallBlockService.limparRegistros();
    if (!mounted) return;
    setState(() {
      _st = s;
      _registros = const [];
    });
  }

  /// Cartão «Relatório de chamadas»: Hoje · Mês · Ano; toque abre em tela cheia.
  Widget _cardRelatorio() {
    final agora = DateTime.now();
    int conta(bool Function(DateTime) f) => _registros.where((r) => f(r.quando)).length;
    final hoje = conta((d) => d.year == agora.year && d.month == agora.month && d.day == agora.day);
    final mes = conta((d) => d.year == agora.year && d.month == agora.month);
    final ano = conta((d) => d.year == agora.year);
    Widget kpi(String t, int n) => Expanded(
          child: Column(children: [
            Text('$n', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _gradOn.first)),
            Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.appTextSecondary)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 10, right: 6),
      child: Material(
        color: _gradOn.first.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _abrirRelatorio,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _gradOn.first.withValues(alpha: 0.25)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(Icons.insights_rounded, size: 18, color: _gradOn.first),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Relatório de chamadas bloqueadas',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: context.appTextPrimary)),
                ),
                Icon(Icons.open_in_full_rounded, size: 18, color: context.appTextSecondary),
              ]),
              const SizedBox(height: 10),
              Row(children: [kpi('Hoje', hoje), kpi('Este mês', mes), kpi('Este ano', ano)]),
              const SizedBox(height: 6),
              Text('Gráficos, quem mais ligou e a lista dos números · toque para abrir',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.appTextMuted)),
            ]),
          ),
        ),
      ),
    );
  }

  String _dataHora(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} às ${two(d.hour)}:${two(d.minute)}';
  }

  ({String label, Color color, IconData icon}) _statusInfo() {
    if (!_st.roleAvailable) {
      return (
        label: _st.sdkInt > 0 && _st.sdkInt < 29
            ? 'Não suportado (exige Android 10+)'
            : 'Não suportado neste aparelho',
        color: AppColors.logoSilver,
        icon: Icons.block_rounded,
      );
    }
    if (_st.active) {
      return (
        label: 'Ativo',
        color: AppColors.success,
        icon: Icons.verified_rounded,
      );
    }
    if (_st.needsPermission) {
      return (
        label: 'Precisa de permissão',
        color: AppColors.amber,
        icon: Icons.warning_amber_rounded,
      );
    }
    return (
      label: 'Desligado',
      color: AppColors.textMuted,
      icon: Icons.power_settings_new_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!CallBlockService.platformSupported) return const SizedBox.shrink();

    final on = _st.enabled;
    final info = _statusInfo();
    final accent = on ? _gradOn.first : AppColors.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          color: on ? null : ModernModuleUI.cardBg(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: on
                ? _gradOn.first.withValues(alpha: 0.45)
                : ModernModuleUI.subtleBorder(context),
          ),
          gradient: on
              ? LinearGradient(
                  colors: [
                    _gradOn.first.withValues(alpha: 0.10),
                    ModernModuleUI.cardBg(context),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ModernModuleUI.iconBadge(
                  icon: Icons.phone_disabled_rounded,
                  gradient: on ? _gradOn : _gradOff,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bloquear chamadas de desconhecidos',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: context.appTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Recusa ligações de números que não estão nos seus '
                        'contatos.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: context.appTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_loading || _busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  Switch(
                    value: on,
                    activeThumbColor: _gradOn.first,
                    onChanged: _onToggle,
                  ),
              ],
            ),
            if (!_loading) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _chip(info.label, info.color, info.icon),
                    if (_st.roleAvailable && (on || _st.blockedCount > 0))
                      _chip(
                        _st.blockedCount == 1
                            ? '1 chamada bloqueada'
                            : '${_st.blockedCount} chamadas bloqueadas',
                        AppColors.primary,
                        Icons.call_end_rounded,
                      ),
                  ],
                ),
              ),
              if (_st.lastBlockedAt != null && _st.blockedCount > 0) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Última recusada em ${_dataHora(_st.lastBlockedAt!)}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: context.appTextMuted,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _zerarContador,
                      icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                      label: const Text('Limpar registros'),
                    ),
                  ],
                ),
              ],
              if (_st.roleAvailable && (on || _registros.isNotEmpty || _st.blockedCount > 0))
                _cardRelatorio(),
              if (_st.roleAvailable)
                Padding(
                  padding: const EdgeInsets.only(top: 10, right: 6),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF2563EB)]),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF7C3AED).withValues(alpha: 0.30), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () async {
                        await CallBlockConfigPage.abrir(context);
                        if (mounted) _refresh();
                      },
                      icon: const Icon(Icons.tune_rounded, size: 19),
                      label: const Text('Permitidos, bloqueados e silenciar',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
              if (_st.needsPermission && _st.roleAvailable) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    !_st.contactsGranted
                        ? 'Falta liberar o acesso aos contatos. Enquanto isso, '
                            'nenhuma ligação é bloqueada.'
                        : 'Falta escolher o WISDOMAPP como app de '
                            'identificação de chamadas e spam.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: context.appTextSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: _busy ? null : _concederPendente,
                    icon: const Icon(Icons.lock_open_rounded, size: 18),
                    label: const Text('Conceder permissão'),
                  ),
                ),
              ],
              if (!_st.roleAvailable) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    _st.sdkInt > 0 && _st.sdkInt < 29
                        ? 'O Android deste aparelho é anterior ao 10 e não '
                            'permite que outro app filtre ligações.'
                        : 'Este aparelho não oferece a triagem de chamadas '
                            'por outro app.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: context.appTextMuted,
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Prévia moderna do bloqueio: o que acontece, as 2 autorizações (com o
/// status de cada) e a garantia de privacidade — um botão «Ativar agora».
class _PreviaBloqueioSheet extends StatelessWidget {
  const _PreviaBloqueioSheet({required this.contatosOk, required this.papelOk});

  final bool contatosOk;
  final bool papelOk;

  @override
  Widget build(BuildContext context) {
    final bg = ModernModuleUI.cardBg(context);
    Widget passo(int n, IconData icone, String titulo, String texto, bool ok) {
      final cor = ok ? const Color(0xFF16A34A) : const Color(0xFFF97316);
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cor.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: cor.withValues(alpha: 0.16),
              child: Icon(ok ? Icons.check_rounded : icone, color: cor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ok ? '$titulo · já autorizado' : '$n. $titulo',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: context.appTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    texto,
                    style: TextStyle(fontSize: 12.5, height: 1.35, color: context.appTextSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(26),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFEF4444), Color(0xFFF97316)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.phone_disabled_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bloquear desconhecidos',
                            style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Só toca quem está nos seus contatos.',
                            style: TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Ligações de números fora dos contatos (e números ocultos) são '
                      'recusadas na hora — continuam no histórico do telefone.',
                      style: TextStyle(fontSize: 13.5, height: 1.4, color: context.appTextPrimary),
                    ),
                    const SizedBox(height: 14),
                    passo(1, Icons.contacts_rounded, 'Acesso aos contatos',
                        'Para saber quem está salvo no seu telefone.', contatosOk),
                    passo(2, Icons.verified_user_rounded, 'App de identificação de chamadas',
                        'O Android pergunta se o WISDOMAPP pode filtrar as ligações.', papelOk),
                    Row(
                      children: [
                        Icon(Icons.lock_rounded, size: 16, color: context.appTextSecondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'O app só vê o número de quem liga. Não grava ligações, não lê '
                            'seu histórico e não envia seus contatos para lugar nenhum.',
                            style: TextStyle(fontSize: 11.5, color: context.appTextSecondary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.shield_rounded),
                      label: const Text('Ativar agora', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Agora não'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
