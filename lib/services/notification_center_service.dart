import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/agenda_alert_queue_item.dart';
import '../models/notification_center_entry.dart';
import '../utils/finance_transactions_realtime.dart';
import 'agenda_managed_queue_service.dart';
import 'notification_center_store.dart';

/// Snapshot leve da central — badge + lista já filtrada.
class NotificationCenterSnapshot {
  const NotificationCenterSnapshot({
    required this.entries,
    required this.badgeCount,
  });

  final List<NotificationCenterEntry> entries;
  final int badgeCount;

  static const empty = NotificationCenterSnapshot(entries: [], badgeCount: 0);
}

class _SharedWatch {
  _SharedWatch(this.uid) {
    _controller = StreamController<NotificationCenterSnapshot>.broadcast(
      onListen: _onListen,
      onCancel: _onCancel,
    );
  }

  final String uid;
  late final StreamController<NotificationCenterSnapshot> _controller;
  int _listeners = 0;

  List<AgendaAlertQueueItem> _agenda = const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _finance = const [];
  List<NotificationCenterEntry> _pushInbox = const [];
  Set<String> _dismissed = {};

  final List<StreamSubscription<dynamic>> _subs = [];
  void Function()? _storeListener;
  Timer? _rebuildDebounce;

  Stream<NotificationCenterSnapshot> get stream => _controller.stream;

  void _onListen() {
    _listeners++;
    if (_listeners != 1) return;

    _storeListener = () => _scheduleRebuild();
    NotificationCenterStore.instance.revision.addListener(_storeListener!);

    _subs.add(
      AgendaManagedQueueService.watchManagedQueue(uid).listen((items) {
        _agenda = items;
        _scheduleRebuild();
      }, onError: (_) {}),
    );

    _subs.add(
      financeTransactionsPendingSnapshots(
        uid: uid,
        type: 'expense',
        limit: NotificationCenterService._financeLimit,
      ).listen((snap) {
        _finance = snap.docs;
        _scheduleRebuild();
      }, onError: (_) {}),
    );

    unawaited(_primeFromLocalCache());
    _scheduleRebuild();
  }

  /// Inbox local + último snapshot — pintura imediata offline.
  Future<void> _primeFromLocalCache() async {
    try {
      _pushInbox = await NotificationCenterStore.instance.pushInboxEntries();
      _dismissed = await NotificationCenterStore.instance.dismissedIds();
    } catch (_) {
      return;
    }
    final peek = NotificationCenterService._compose(
      _agenda,
      _finance,
      _pushInbox,
      _dismissed,
    );
    if (peek.entries.isNotEmpty && !_controller.isClosed) {
      NotificationCenterService._rememberPeek(uid, peek);
      _controller.add(peek);
    }
  }

  void _scheduleRebuild() {
    _rebuildDebounce?.cancel();
    _rebuildDebounce = Timer(const Duration(milliseconds: 96), () {
      unawaited(_rebuild());
    });
  }

  Future<void> forceRebuildSilent() async {
    _rebuildDebounce?.cancel();
    await _rebuild();
  }

  void _onCancel() {
    _listeners--;
    if (_listeners > 0) return;
    _rebuildDebounce?.cancel();
    _rebuildDebounce = null;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    if (_storeListener != null) {
      NotificationCenterStore.instance.revision.removeListener(_storeListener!);
      _storeListener = null;
    }
  }

  Future<void> _rebuild() async {
    // Falha no armazenamento local não pode impedir a emissão (a central
    // ficava girando para sempre) — segue com o que já tem em memória.
    try {
      _dismissed = await NotificationCenterStore.instance.dismissedIds();
    } catch (_) {}
    try {
      _pushInbox = await NotificationCenterStore.instance.pushInboxEntries();
    } catch (_) {}
    if (_controller.isClosed) return;
    final snap = NotificationCenterService._compose(
      _agenda,
      _finance,
      _pushInbox,
      _dismissed,
    );
    NotificationCenterService._rememberPeek(uid, snap);
    _controller.add(snap);
  }

  void dispose() {
    _onCancel();
    unawaited(_controller.close());
  }
}

/// Agrega agendaAlerts + contas pendentes + inbox local sem bloquear UI.
class NotificationCenterService {
  NotificationCenterService._();

  static const int _financeLimit = 15;
  static const int _agendaLimit = 320;

  static final Map<String, _SharedWatch> _shared = {};
  static final Map<String, NotificationCenterSnapshot> _peekByUid = {};

  /// Último snapshot conhecido — evita badge/lista piscar offline.
  static NotificationCenterSnapshot? peek(String uid) {
    if (uid.isEmpty) return null;
    return _peekByUid[uid];
  }

  static Stream<NotificationCenterSnapshot> watch(String uid) {
    if (uid.isEmpty) return Stream.value(NotificationCenterSnapshot.empty);
    return _shared.putIfAbsent(uid, () => _SharedWatch(uid)).stream;
  }

  /// Chamado ao voltar a internet — sem banner, sem reload visível.
  static void silentResyncAfterReconnect(String uid) {
    if (uid.isEmpty) return;
    unawaited(NotificationCenterStore.instance.silentResyncAfterReconnect());
    final w = _shared[uid];
    if (w != null) {
      unawaited(w.forceRebuildSilent());
    }
  }

  static void _rememberPeek(String uid, NotificationCenterSnapshot snap) {
    _peekByUid[uid] = snap;
  }

  static NotificationCenterSnapshot _compose(
    List<AgendaAlertQueueItem> agenda,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> finance,
    List<NotificationCenterEntry> pushInbox,
    Set<String> dismissed,
  ) {
    final map = <String, NotificationCenterEntry>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final agendaSlice = agenda.length > _agendaLimit
        ? agenda.take(_agendaLimit).toList()
        : agenda;

    for (final item in agendaSlice) {
      if (item.isPending) {
        final eventDay = DateTime(
          item.eventAt.year,
          item.eventAt.month,
          item.eventAt.day,
        );
        if (eventDay.isBefore(today)) continue;
      }
      final e = NotificationCenterEntry.fromAgendaAlert(item);
      if (e == null || dismissed.contains(e.id)) continue;
      map[e.id] = e;
    }

    for (final doc in finance) {
      final e = NotificationCenterEntry.fromFinanceDoc(doc);
      if (e == null || dismissed.contains(e.id)) continue;
      map.putIfAbsent(e.id, () => e);
    }

    for (final e in pushInbox) {
      if (dismissed.contains(e.id)) continue;
      final existing = map[e.id];
      if (existing != null && existing.isPending && !e.isPending) {
        map[e.id] = e;
      } else {
        map.putIfAbsent(e.id, () => e);
      }
    }

    final entries = map.values.toList()
      ..sort((a, b) {
        final aAt = a.eventAt ?? a.notifiedAt ?? DateTime(2100);
        final bAt = b.eventAt ?? b.notifiedAt ?? DateTime(2100);
        final byDate = aAt.compareTo(bAt);
        if (byDate != 0) return byDate;
        return a.title.compareTo(b.title);
      });

    return NotificationCenterSnapshot(
      entries: entries,
      badgeCount: entries.length,
    );
  }
}
