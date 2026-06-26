import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/material.dart';
import '../models/shift_location.dart';
import '../theme/app_colors.dart';
import '../utils/firestore_user_doc_id.dart';
import 'edit_location_screen.dart';

/// Pré-cadastros: `users/{uid}/locations`.
/// Carrega com [get] (cache+servidor) e mantém [snapshots] — evita `StreamBuilder` preso
/// em `ConnectionState.waiting` em Android/Web quando o 1.º evento atraso ou falha de rede.
class LocationsScreen extends StatefulWidget {
  final String uid;

  const LocationsScreen({super.key, required this.uid});

  @override
  State<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends State<LocationsScreen> {
  /// Evita anexar [snapshots] de uma chamada antiga a [_startListening] após nova sessão/auth.
  int _listenGen = 0;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  StreamSubscription<fa.User?>? _authStateSub;
  Timer? _authWaitTimer;

  /// Sentinela: sessão Firestore ainda não apareceu após espera (web/restauração de token).
  static final Object _sessionWaitSentinel = Object();

  /// null = ainda sem qualquer carga com sucesso
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _docs;
  Object? _loadError;

  /// Só o [`request.auth.uid`] passa nas regras; sem sessão, não abrir leitura (evita `permission-denied` na web).
  String? get _sessionUid => firestoreSessionUid();

  bool get _hasSession {
    final u = firestoreUserDocIdStrictFromSession();
    return u.isNotEmpty;
  }

  CollectionReference<Map<String, dynamic>>? _refForSession() {
    final u = firestoreUserDocIdStrictFromSession();
    if (u.isEmpty) return null;
    return FirebaseFirestore.instance.collection('users').doc(u).collection('locations');
  }

  Future<void> _ensureFreshAuthToken() async {
    final u = fa.FirebaseAuth.instance.currentUser;
    if (u == null) return;
    try {
      await u.getIdToken(true);
    } catch (_) {}
  }

  static bool _isTransientFirestoreError(Object e) {
    if (e is FirebaseException) {
      const transient = {
        'unavailable',
        'deadline-exceeded',
        'resource-exhausted',
        'aborted',
        'cancelled',
      };
      return transient.contains(e.code);
    }
    return false;
  }

  int _nameSort(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final na = _displayNameKey(a.data()).toLowerCase();
    final nb = _displayNameKey(b.data()).toLowerCase();
    return na.compareTo(nb);
  }

  /// Nome legível para ordenar/filtrar (inclui label/título/sigla legados).
  static String _displayNameKey(Map<String, dynamic> m) {
    var n = (m['name'] ?? '').toString().trim();
    if (n.isNotEmpty) return n;
    n = (m['label'] ?? m['title'] ?? '').toString().trim();
    if (n.isNotEmpty) return n;
    return (m['abbreviation'] ?? '').toString().trim();
  }

  /// Qualquer documento não vazio na coleção é um plantão — evita “sumir” pré-cadastro por filtro agressivo.
  static bool _isDisplayable(Map<String, dynamic> m) {
    if (m.isEmpty) return false;
    if (_displayNameKey(m).isNotEmpty) return true;
    return (m['abbreviation'] ?? '').toString().trim().isNotEmpty ||
        (m['startTime'] ?? '').toString().trim().isNotEmpty ||
        (m['endTime'] ?? '').toString().trim().isNotEmpty;
  }

  /// Garante [name] para [ShiftLocation.fromMap] em documentos muito antigos ou só com sigla.
  static Map<String, dynamic> _mapForModel(Map<String, dynamic> m) {
    final out = Map<String, dynamic>.from(m);
    if ((out['name'] ?? '').toString().trim().isNotEmpty) return out;
    final l = (out['label'] ?? out['title'] ?? '').toString().trim();
    if (l.isNotEmpty) {
      out['name'] = l;
      return out;
    }
    final abbr = (out['abbreviation'] ?? '').toString().trim();
    if (abbr.isNotEmpty) {
      out['name'] = abbr;
      return out;
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    // Web/sessão: a subscrição inicial pode apontar para o path errado; ao alinhar a sessão, volta a inscrever [users/uid/locations].
    _authStateSub = fa.FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted) _startListening();
    });
    _startListening();
  }

  @override
  void didUpdateWidget(LocationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      setState(() {
        _loadError = null;
        _docs = null;
      });
      _startListening();
    }
  }

  @override
  void dispose() {
    _authWaitTimer?.cancel();
    _authStateSub?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _fetchOnce({required int gen}) async {
    final ref = _refForSession();
    if (ref == null) return;
    if (!mounted || gen != _listenGen) return;

    // Cache primeiro: se já tivermos algo no IndexedDB/disk, mostramos
    // **imediatamente** ao usuário (evita tela vazia/erro quando rede falha).
    // Mesmo que o cache retorne 0 docs, prosseguimos para o servidor —
    // não bloqueamos o build com tela de erro.
    try {
      final cached = await ref.get(const GetOptions(source: Source.cache));
      if (!mounted || gen != _listenGen) return;
      if (cached.docs.isNotEmpty) {
        setState(() {
          _loadError = null;
          _setDocs(cached.docs);
        });
      }
    } catch (_) {
      // Cache miss/erro — segue para o caminho de rede normal.
    }
    if (!mounted || gen != _listenGen) return;

    await _ensureFreshAuthToken();
    if (!mounted || gen != _listenGen) return;

    const sources = <Source?>[
      Source.serverAndCache,
      null,
      Source.server,
      Source.cache,
    ];

    Object? lastErr;
    for (var attempt = 0; attempt < 5; attempt++) {
      if (!mounted || gen != _listenGen) return;
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: 200 + 180 * attempt));
        if (!mounted || gen != _listenGen) return;
      }

      for (final src in sources) {
        try {
          final snap = src == null
              ? await ref.get()
              : await ref.get(GetOptions(source: src));
          if (!mounted || gen != _listenGen) return;
          setState(() {
            _loadError = null;
            _setDocs(snap.docs);
          });
          return;
        } catch (e) {
          lastErr = e;
          if (e is FirebaseException && e.code == 'permission-denied') {
            if (!mounted || gen != _listenGen) return;
            // Se já temos dados de cache, NÃO sobrescrevemos a tela boa por
            // erro — apenas guardamos o erro para um banner amarelo.
            setState(() => _loadError = e);
            return;
          }
        }
      }

      final err = lastErr;
      if (err != null && !_isTransientFirestoreError(err)) {
        break;
      }
    }

    if (!mounted || gen != _listenGen) return;
    if (lastErr != null) {
      setState(() => _loadError = lastErr);
    }
  }

  void _attachSnapshots(CollectionReference<Map<String, dynamic>> ref, {required int gen}) {
    _sub?.cancel();
    _sub = ref.snapshots().listen(
      (snap) {
        if (!mounted || gen != _listenGen) return;
        setState(() {
          _loadError = null;
          _setDocs(snap.docs);
        });
      },
      onError: (Object e) {
        if (!mounted || gen != _listenGen) return;
        if (_isTransientFirestoreError(e)) {
          unawaited(_fetchOnce(gen: gen));
          return;
        }
        setState(() => _loadError = e);
      },
      cancelOnError: false,
    );
  }

  void _startListening() {
    _sub?.cancel();
    final gen = ++_listenGen;

    final ref = _refForSession();
    if (ref == null) {
      _authWaitTimer?.cancel();
      _authWaitTimer = Timer(const Duration(seconds: 22), () {
        if (!mounted || gen != _listenGen) return;
        if (_refForSession() != null) return;
        if (_docs != null) return;
        setState(() => _loadError = _sessionWaitSentinel);
      });
      if (mounted) setState(() {});
      return;
    }

    _authWaitTimer?.cancel();
    _authWaitTimer = null;

    unawaited(() async {
      await _ensureFreshAuthToken();
      if (!mounted || gen != _listenGen) return;
      await _fetchOnce(gen: gen);
      if (!mounted || gen != _listenGen) return;
      _attachSnapshots(ref, gen: gen);
    }());
  }

  static String? _hintForError(Object? e) {
    if (identical(e, _sessionWaitSentinel)) {
      return 'Confirme o login (web pode demorar a restaurar a sessão). Atualize a página ou saia e entre de novo.';
    }
    if (e is FirebaseException && e.code == 'permission-denied') {
      return 'Permissão negada (sessão). Saia, entre de novo e reabra Configurações → Plantões.';
    }
    if (e is FirebaseException && e.code == 'unavailable') {
      return 'Serviço temporariamente indisponível. Tente dentro de segundos.';
    }
    if (e is FirebaseException && e.code == 'deadline-exceeded') {
      return 'Tempo esgotado na rede. Verifique a ligação e tente de novo.';
    }
    return null;
  }

  void _setDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final raw = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs)..sort(_nameSort);
    _docs = raw.where((d) => _isDisplayable(d.data())).toList();
  }

  void _retry() {
    _authWaitTimer?.cancel();
    setState(() {
      _loadError = null;
    });
    _startListening();
  }

  /// Quando o cache local (IndexedDB/disco) está corrompido, todas as
  /// tentativas com cache falham e o usuário vê "Não foi possível carregar
  /// os plantões". Este botão limpa a persistência do Firestore e força
  /// nova leitura do servidor — recupera a tela sem ter de sair e entrar.
  Future<void> _clearCacheAndRetry() async {
    setState(() => _loadError = null);
    _sub?.cancel();
    try {
      await FirebaseFirestore.instance.terminate();
    } catch (_) {}
    try {
      await FirebaseFirestore.instance.clearPersistence();
    } catch (_) {}
    if (!mounted) return;
    _startListening();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cache local limpo. Buscando do servidor…'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onRefresh() async {
    await _fetchOnce(gen: _listenGen);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null && _docs == null) {
      final sessionOnly = identical(_loadError, _sessionWaitSentinel);
      return Scaffold(
        appBar: AppBar(
          title: const Text('Plantões'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 48, color: Colors.orange.shade700),
                const SizedBox(height: 12),
                Text(
                  sessionOnly
                      ? 'A sessão com o servidor ainda não ficou pronta neste dispositivo.'
                      : 'Não foi possível carregar os plantões. Os dados permanecem no servidor — verifique a rede e tente de novo.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.35),
                ),
                if (_hintForError(_loadError) != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _hintForError(_loadError)!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.brown.shade800, height: 1.3),
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      title: const Text(
                        'Mostrar detalhe técnico (para o suporte)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      children: [
                        SelectableText(
                          _loadError.toString(),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Tentar novamente'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _clearCacheAndRetry,
                  icon: const Icon(Icons.cleaning_services_rounded),
                  label: const Text('Limpar cache local e tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_docs == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Plantões'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                if (!_hasSession) ...[
                  const SizedBox(height: 20),
                  Text(
                    'A ligar à sua conta…',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Na web, o login pode levar um instante. Se demorar, use Tentar abaixo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.3),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonalIcon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final docs = _docs!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plantões'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_loadError != null) ...[
              Material(
                color: Colors.amber.shade50,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_tethering_error_rounded, color: Colors.amber.shade900, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'A lista pode estar desatualizada. Puxar para atualizar ou tente de novo em instantes.',
                          style: TextStyle(fontSize: 12, height: 1.25),
                        ),
                      ),
                      TextButton(
                        onPressed: _retry,
                        child: const Text('Reconectar'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            Expanded(
              child: docs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.event_note_rounded,
                                size: 64, color: AppColors.textMuted.withValues(alpha: 0.5)),
                            const SizedBox(height: 16),
                            Text(
                              'Nenhum tipo de plantão cadastrado',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16, color: AppColors.textMuted),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Toque em + para criar o primeiro (ex: Ordinário, Case Diurno, Reforço)',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _onRefresh,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 80 + MediaQuery.paddingOf(context).bottom),
                        itemCount: docs.length,
                        itemBuilder: (context, i) {
                          final doc = docs[i];
                          late final ShiftLocation loc;
                          try {
                            loc = ShiftLocation.fromMap(doc.id, _mapForModel(doc.data()));
                          } catch (e, st) {
                            assert(() {
                              debugPrint('LocationsScreen: doc ${doc.id} — $e\n$st');
                              return true;
                            }());
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                leading: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                                title: const Text('Plantão com dados inválidos'),
                                subtitle: Text(
                                  doc.id,
                                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                                trailing: IconButton(
                                  tooltip: 'Excluir',
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Remover registro'),
                                        content: const Text(
                                          'Este documento não pôde ser lido. Excluir mesmo assim?',
                                        ),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                          FilledButton(
                                            onPressed: () => Navigator.pop(ctx, true),
                                            style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                            child: const Text('Excluir'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok == true) await doc.reference.delete();
                                  },
                                ),
                              ),
                            );
                          }
                          return _LocationCard(
                            location: loc,
                            onTap: () async {
                              final u = _sessionUid;
                              if (u == null) return;
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => EditLocationScreen(uid: u, location: loc),
                                ),
                              );
                            },
                            onDelete: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Excluir local'),
                                  content: Text(
                                    'Excluir "${loc.name.isNotEmpty ? loc.name : (loc.abbreviation.isNotEmpty ? loc.abbreviation : "este plantão")}"? '
                                    'Plantões já agendados não serão removidos.',
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                      child: const Text('Excluir'),
                                    ),
                                  ],
                                ),
                              );
                              if (ok == true) await doc.reference.delete();
                            },
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final u = _sessionUid;
          if (u == null) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EditLocationScreen(uid: u),
            ),
          );
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Novo'),
        backgroundColor: AppColors.success,
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  final ShiftLocation location;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _LocationCard({required this.location, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final title = location.name.isNotEmpty
        ? location.name
        : (location.abbreviation.isNotEmpty ? location.abbreviation : 'Plantão');
    final swatch = AppColors.vividShift(location.color);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: swatch,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: swatch.withValues(alpha: 0.92),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: swatch.withValues(alpha: 0.42),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${location.startTime} - ${location.endTime}',
                      style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (v) {
                  if (v == 'delete') onDelete();
                  if (v == 'edit') onTap();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: ListTile(title: Text('Editar'), leading: Icon(Icons.edit_rounded), contentPadding: EdgeInsets.zero)),
                  const PopupMenuItem(value: 'delete', child: ListTile(title: Text('Excluir'), leading: Icon(Icons.delete_outline_rounded, color: Colors.red), contentPadding: EdgeInsets.zero)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
