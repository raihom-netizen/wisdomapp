import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/commitment_symbols.dart';
import '../models/notification_center_entry.dart';
import '../services/fcm_local_notification_presenter.dart';
import '../services/notification_center_service.dart';
import '../services/notification_center_store.dart';
import '../services/user_profile_startup_cache.dart';
import '../theme/app_colors.dart';
import '../theme/theme_context.dart';
import '../utils/finance_transactions_hub.dart';
import '../utils/firestore_user_doc_id.dart';
import '../widgets/compromisso_contact_chips.dart';
import '../widgets/finance_transaction_edit_dialog.dart';

/// Abas legadas (deep link de push). A UI moderna usa só Todos / Financeiro /
/// Compromissos — o WisdomApp não tem Plantões nem Audiências.
enum NotificationCenterTab {
  escalas,
  compromissos,
  audiencias, // legado — vira Compromissos
  contas,
}

/// Mantido por compatibilidade (contagens/atalhos antigos).
const List<NotificationCenterTab> kNotificationCenterVisibleTabs = [
  NotificationCenterTab.compromissos,
  NotificationCenterTab.contas,
];

enum _Filtro { todos, financeiro, compromissos }

class _Visual {
  const _Visual(this.cor, this.cor2, this.icone, this.rotulo);
  final Color cor;
  final Color cor2;
  final IconData icone;
  final String rotulo;
}

const _vCompromisso = _Visual(
    Color(0xFF2563EB), Color(0xFF6366F1), Icons.event_rounded, 'Compromisso');
const _vPagar = _Visual(Color(0xFFDC2626), Color(0xFFF97316),
    Icons.arrow_upward_rounded, 'A pagar');
const _vReceber = _Visual(Color(0xFF059669), Color(0xFF10B981),
    Icons.arrow_downward_rounded, 'A receber');
const _vOutros = _Visual(
    Color(0xFF7C3AED), Color(0xFFA855F7), Icons.campaign_rounded, 'Aviso');

_Visual _visualDe(NotificationCenterEntry e) {
  switch (e.kind) {
    case NotificationCenterKind.financeiro:
      return e.financeType == 'income' ? _vReceber : _vPagar;
    case NotificationCenterKind.compromisso:
    case NotificationCenterKind.audiencia:
      return _vCompromisso;
    default:
      return _vOutros;
  }
}

/// Central de avisos — visual do Controle Total: cards coloridos por tipo,
/// agrupados em Atrasados / Hoje / Amanhã / Próximos, ações rápidas e
/// remoção automática 24 h depois do evento.
class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key, this.initialTab});

  /// Aba inicial (deep link a partir de push/local notification tap).
  final NotificationCenterTab? initialTab;

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  late _Filtro _filtro;
  Stream<NotificationCenterSnapshot>? _stream;
  String? _streamUid;
  final Set<String> _ocupados = {};

  String get _uid => firestoreUserDocIdForAppShell(
        FirebaseAuth.instance.currentUser?.uid ?? '',
      );

  @override
  void initState() {
    super.initState();
    _filtro = switch (widget.initialTab) {
      NotificationCenterTab.contas => _Filtro.financeiro,
      NotificationCenterTab.compromissos ||
      NotificationCenterTab.audiencias =>
        _Filtro.compromissos,
      _ => _Filtro.todos,
    };
    unawaited(FcmLocalNotificationPresenter.limparBandejaAntiga());
  }

  Stream<NotificationCenterSnapshot> _streamFor(String uid) {
    if (_stream == null || _streamUid != uid) {
      _streamUid = uid;
      _stream = NotificationCenterService.watch(uid);
    }
    return _stream!;
  }

  bool _passaFiltro(NotificationCenterEntry e) => switch (_filtro) {
        _Filtro.todos => true,
        _Filtro.financeiro => e.kind == NotificationCenterKind.financeiro,
        _Filtro.compromissos => e.kind == NotificationCenterKind.compromisso ||
            e.kind == NotificationCenterKind.audiencia,
      };

  // ── Ações ────────────────────────────────────────────────────────────────

  Future<void> _dispensar(NotificationCenterEntry e) async {
    await NotificationCenterStore.instance.dismiss([e.id]);
  }

  Future<void> _marcarTodosComoLidos(List<NotificationCenterEntry> itens) async {
    if (itens.isEmpty) return;
    await NotificationCenterStore.instance.dismissAll(itens.map((e) => e.id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(itens.length == 1
            ? '1 aviso marcado como lido.'
            : '${itens.length} avisos marcados como lidos.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _snack(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: erro ? AppColors.error : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Concluir compromisso: marca o compromisso como realizado (não apaga) e
  /// tira o aviso da central.
  Future<void> _concluir(NotificationCenterEntry e) async {
    if (e.sourceType != 'reminder' || e.sourceId.isEmpty || _uid.isEmpty) {
      await _dispensar(e);
      return;
    }
    setState(() => _ocupados.add(e.id));
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('reminders')
          .doc(e.sourceId)
          .set({
        'done': true,
        'status': 'REALIZADO',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 15));
      await _dispensar(e);
      _snack('Compromisso concluído.');
    } catch (err) {
      _snack('Não foi possível concluir: ${err.toString().split('\n').first}',
          erro: true);
    } finally {
      if (mounted) setState(() => _ocupados.remove(e.id));
    }
  }

  /// Pagar/Receber: abre o mesmo editor do Financeiro já com o lançamento.
  Future<void> _pagarOuReceber(NotificationCenterEntry e) async {
    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final profile = UserProfileStartupCache.getSync(authUid);
    if (e.sourceId.isEmpty || _uid.isEmpty || profile == null) {
      _snack('Abra o Financeiro para dar baixa neste lançamento.');
      return;
    }
    setState(() => _ocupados.add(e.id));
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('transactions')
          .doc(e.sourceId)
          .get()
          .timeout(const Duration(seconds: 15));
      final data = snap.data();
      if (!mounted) return;
      if (data == null) {
        await _dispensar(e);
        _snack('Este lançamento não existe mais.');
        return;
      }
      final saved = await showFinanceTransactionEditDialog(
        context: context,
        uid: authUid,
        profile: profile,
        docId: e.sourceId,
        current: data,
        type: (data['type'] ?? e.financeType).toString(),
        logModulo: 'Avisos',
      );
      if (saved) FinanceTransactionsHub.notifyMutated(uid: _uid);
    } catch (err) {
      _snack(
          'Não foi possível abrir o lançamento: '
          '${err.toString().split('\n').first}',
          erro: true);
    } finally {
      if (mounted) setState(() => _ocupados.remove(e.id));
    }
  }

  Future<void> _ver(NotificationCenterEntry e) async {
    final v = _visualDe(e);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.appSurface,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Bolha(entry: e, visual: v, size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      e.title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: ctx.appTextPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Pill(texto: _quando(e), cor: v.cor),
              if (e.body.trim().isNotEmpty && e.body.trim() != e.title.trim())
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    e.body,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.4,
                      color: ctx.appTextSecondary,
                    ),
                  ),
                ),
              if (e.linkLocalizacao.isNotEmpty || e.contatoWhatsApp.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: CompromissoContactChips(
                    linkLocalizacao: e.linkLocalizacao,
                    contatoWhatsApp: e.contatoWhatsApp,
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                'Este aviso sai sozinho da central 24 h depois do horário.',
                style: TextStyle(fontSize: 12, color: ctx.appTextMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Datas ────────────────────────────────────────────────────────────────

  static DateTime _dia(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _quando(NotificationCenterEntry e) {
    final ref = e.eventAt ?? e.notifiedAt;
    if (ref == null) return 'Sem data';
    final agora = DateTime.now();
    final hoje = _dia(agora);
    final d = _dia(ref);
    final temHora = ref.hour != 0 || ref.minute != 0;
    final hora = temHora ? ' · ${DateFormat('HH:mm').format(ref)}' : '';
    final diff = ref.difference(agora);
    var relativo = '';
    if (temHora) {
      if (diff.inMinutes.abs() < 1) {
        relativo = ' · agora';
      } else if (diff.isNegative && diff.inMinutes > -60) {
        relativo = ' · há ${-diff.inMinutes} min';
      } else if (diff.isNegative && diff.inHours > -24) {
        relativo = ' · há ${-diff.inHours} h';
      } else if (!diff.isNegative && diff.inMinutes < 60) {
        relativo = ' · em ${diff.inMinutes} min';
      } else if (!diff.isNegative && diff.inHours < 12) {
        relativo = ' · em ${diff.inHours} h';
      }
    }
    if (d == hoje) return 'Hoje$hora$relativo';
    if (d == hoje.add(const Duration(days: 1))) return 'Amanhã$hora$relativo';
    if (d == hoje.subtract(const Duration(days: 1))) {
      return 'Ontem$hora$relativo';
    }
    final semana = DateFormat('EEE, dd/MM', 'pt_BR').format(ref);
    return '${semana[0].toUpperCase()}${semana.substring(1)}$hora';
  }

  static int _grupo(NotificationCenterEntry e) {
    final ref = e.eventAt ?? e.notifiedAt;
    if (ref == null) return 3;
    final hoje = _dia(DateTime.now());
    final d = _dia(ref);
    if (d.isBefore(hoje)) return 0; // atrasados (ainda dentro das 24 h)
    if (d == hoje) return 1;
    if (d == hoje.add(const Duration(days: 1))) return 2;
    return 3;
  }

  static const _titulosGrupo = ['Atrasados', 'Hoje', 'Amanhã', 'Próximos'];
  static const _iconesGrupo = [
    Icons.history_rounded,
    Icons.today_rounded,
    Icons.event_rounded,
    Icons.date_range_rounded,
  ];

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkMode;
    final uid = _uid;
    return Scaffold(
      backgroundColor: dark ? context.appScaffold : const Color(0xFFF4F6FB),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: AppColors.logoGradient,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Avisos',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2)),
      ),
      body: uid.isEmpty
          ? Center(
              child: Text('Entre na sua conta para ver os avisos.',
                  style: TextStyle(color: context.appTextMuted)),
            )
          : StreamBuilder<NotificationCenterSnapshot>(
              stream: _streamFor(uid),
              initialData: NotificationCenterService.peek(uid) ??
                  NotificationCenterSnapshot.empty,
              builder: (context, snap) {
                final todos = (snap.data?.entries ?? const [])
                    .where((e) => e.tipoVisivel && !e.expirado())
                    .toList();
                final carregando =
                    snap.connectionState == ConnectionState.waiting &&
                        todos.isEmpty &&
                        NotificationCenterService.peek(uid) == null;
                if (carregando) {
                  return const Center(child: CircularProgressIndicator());
                }
                final nFin = todos
                    .where((e) => e.kind == NotificationCenterKind.financeiro)
                    .length;
                final nComp = todos
                    .where((e) =>
                        e.kind == NotificationCenterKind.compromisso ||
                        e.kind == NotificationCenterKind.audiencia)
                    .length;
                final visiveis = todos.where(_passaFiltro).toList()
                  ..sort((a, b) {
                    final ra = a.eventAt ?? a.notifiedAt ?? DateTime(2100);
                    final rb = b.eventAt ?? b.notifiedAt ?? DateTime(2100);
                    return ra.compareTo(rb);
                  });

                final grupos =
                    List.generate(4, (_) => <NotificationCenterEntry>[]);
                for (final e in visiveis) {
                  grupos[_grupo(e)].add(e);
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    NotificationCenterService.silentResyncAfterReconnect(uid);
                    await Future<void>.delayed(
                        const Duration(milliseconds: 600));
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      _resumo(todos.length, nFin, nComp),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Somem sozinhos 24 h depois do horário.',
                              style: TextStyle(
                                  fontSize: 12, color: context.appTextMuted),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: visiveis.isEmpty
                                ? null
                                : () => _marcarTodosComoLidos(visiveis),
                            icon: const Icon(Icons.done_all_rounded, size: 18),
                            label: const Text('Marcar todos como lidos'),
                          ),
                        ],
                      ),
                      if (visiveis.isEmpty) _vazio(),
                      for (var g = 0; g < 4; g++)
                        if (grupos[g].isNotEmpty) ...[
                          _cabecalhoGrupo(g, grupos[g].length),
                          for (final e in grupos[g]) _card(e),
                        ],
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _resumo(int total, int nFin, int nComp) {
    Widget card(_Filtro f, String rotulo, int n, IconData ic, List<Color> g) {
      final ativo = _filtro == f;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _filtro = f),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: ativo
                  ? LinearGradient(
                      colors: g,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight)
                  : null,
              color: ativo
                  ? null
                  : (context.isDarkMode ? context.appSurface : Colors.white),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color:
                    ativo ? Colors.transparent : g.first.withValues(alpha: 0.3),
              ),
              boxShadow: ativo
                  ? [
                      BoxShadow(
                        color: g.first.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(ic,
                    size: 20,
                    color: ativo
                        ? Colors.white
                        : (context.isDarkMode
                            ? Color.lerp(g.first, Colors.white, 0.3)
                            : g.first)),
                const SizedBox(height: 6),
                Text(
                  '$n',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: ativo ? Colors.white : context.appTextPrimary,
                  ),
                ),
                Text(
                  rotulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: ativo
                        ? Colors.white.withValues(alpha: 0.9)
                        : context.appTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        card(_Filtro.todos, 'Todos', total, Icons.notifications_active_rounded,
            const [Color(0xFF0B1B4B), Color(0xFF334155)]),
        const SizedBox(width: 10),
        card(_Filtro.financeiro, 'Financeiro', nFin,
            Icons.account_balance_wallet_rounded,
            const [Color(0xFFDC2626), Color(0xFFF97316)]),
        const SizedBox(width: 10),
        card(_Filtro.compromissos, 'Compromissos', nComp, Icons.event_rounded,
            const [Color(0xFF2563EB), Color(0xFF6366F1)]),
      ],
    );
  }

  Widget _cabecalhoGrupo(int g, int n) {
    final cor = g == 0 ? const Color(0xFFDC2626) : context.appTextPrimary;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Row(
        children: [
          Icon(_iconesGrupo[g], size: 18, color: cor),
          const SizedBox(width: 6),
          Text(
            _titulosGrupo[g],
            style: TextStyle(
                fontSize: 14.5, fontWeight: FontWeight.w900, color: cor),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$n',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w900, color: cor)),
          ),
        ],
      ),
    );
  }

  Widget _vazio() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 56),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF059669).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_none_rounded,
                  size: 40, color: Color(0xFF059669)),
            ),
            const SizedBox(height: 14),
            Text('Tudo em dia!',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: context.appTextPrimary)),
            const SizedBox(height: 4),
            Text('Nenhum aviso por aqui.',
                style: TextStyle(color: context.appTextMuted)),
          ],
        ),
      );

  Widget _card(NotificationCenterEntry e) {
    final v = _visualDe(e);
    final dark = context.isDarkMode;
    final fin = e.kind == NotificationCenterKind.financeiro;
    final comp = e.kind == NotificationCenterKind.compromisso ||
        e.kind == NotificationCenterKind.audiencia;
    final ocupado = _ocupados.contains(e.id);
    final atrasado = _grupo(e) == 0;
    final corpo = e.body.trim();

    return Dismissible(
      key: ValueKey('nc-${e.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: const Color(0xFF64748B),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.done_rounded, color: Colors.white),
      ),
      onDismissed: (_) => _dispensar(e),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: dark ? context.appSurface : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: v.cor.withValues(alpha: dark ? 0.45 : 0.25)),
          boxShadow: [
            BoxShadow(
              color:
                  const Color(0xFF0F172A).withValues(alpha: dark ? 0.2 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [v.cor, v.cor2],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _ver(e),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _Bolha(entry: e, visual: v, size: 44),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        e.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                          color: context.appTextPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          _Pill(
                                            texto: _quando(e),
                                            cor: atrasado
                                                ? const Color(0xFFDC2626)
                                                : v.cor,
                                          ),
                                          _Pill(texto: v.rotulo, cor: v.cor2),
                                        ],
                                      ),
                                      if (!fin &&
                                          corpo.isNotEmpty &&
                                          corpo != e.title.trim())
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 6),
                                          child: Text(
                                            corpo,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              height: 1.3,
                                              color: context.appTextSecondary,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (fin && corpo.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Text(
                                      corpo,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                        color: dark
                                            ? Color.lerp(
                                                v.cor, Colors.white, 0.3)
                                            : v.cor,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (ocupado)
                              const LinearProgressIndicator(minHeight: 2)
                            else
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _Acao(
                                    icone: Icons.visibility_rounded,
                                    rotulo: 'Ver',
                                    cor: context.appTextSecondary,
                                    onTap: () => _ver(e),
                                  ),
                                  if (fin && e.sourceId.isNotEmpty)
                                    _Acao(
                                      icone: e.financeType == 'income'
                                          ? Icons.call_received_rounded
                                          : Icons.payments_rounded,
                                      rotulo: e.financeType == 'income'
                                          ? 'Receber'
                                          : 'Pagar',
                                      cor: v.cor,
                                      destaque: true,
                                      onTap: () => _pagarOuReceber(e),
                                    ),
                                  if (comp && e.sourceType == 'reminder')
                                    _Acao(
                                      icone: Icons.check_circle_rounded,
                                      rotulo: 'Concluir',
                                      cor: const Color(0xFF059669),
                                      destaque: true,
                                      onTap: () => _concluir(e),
                                    ),
                                  _Acao(
                                    icone: Icons.close_rounded,
                                    rotulo: 'Dispensar',
                                    cor: context.appTextMuted,
                                    onTap: () => _dispensar(e),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bolha extends StatelessWidget {
  const _Bolha({required this.entry, required this.visual, required this.size});
  final NotificationCenterEntry entry;
  final _Visual visual;
  final double size;

  @override
  Widget build(BuildContext context) {
    final comp = entry.kind == NotificationCenterKind.compromisso ||
        entry.kind == NotificationCenterKind.audiencia;
    final emoji = comp ? suggestCommitmentEmoji(entry.title) : null;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            visual.cor.withValues(alpha: 0.18),
            visual.cor2.withValues(alpha: 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: emoji != null
          ? Text(emoji, style: TextStyle(fontSize: size * 0.5, height: 1))
          : Icon(visual.icone,
              color: context.isDarkMode
                  ? Color.lerp(visual.cor, Colors.white, 0.3)
                  : visual.cor,
              size: size * 0.5),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.texto, required this.cor});
  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDarkMode;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: dark ? 0.22 : 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: dark ? Color.lerp(cor, Colors.white, 0.35) : cor,
        ),
      ),
    );
  }
}

class _Acao extends StatelessWidget {
  const _Acao({
    required this.icone,
    required this.rotulo,
    required this.cor,
    required this.onTap,
    this.destaque = false,
  });
  final IconData icone;
  final String rotulo;
  final Color cor;
  final VoidCallback onTap;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: destaque ? Colors.white : cor,
        backgroundColor: destaque ? cor : cor.withValues(alpha: 0.08),
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle:
            const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
      ),
      icon: Icon(icone, size: 16),
      label: Text(rotulo),
    );
  }
}
