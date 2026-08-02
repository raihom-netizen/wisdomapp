import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../utils/firestore_user_doc_id.dart';
import 'widget_update_service.dart';

/// Escuta alterações locais em scales/reminders (cache Firestore) e dispara refresh do widget.
class WidgetFirestoreLiveSync {
  WidgetFirestoreLiveSync._();

  static const int _horizonDays = 5;
  static const int _queryLimit = 28;
  static const Duration _debounce = Duration(milliseconds: 280);

  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _scalesSub;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _remindersSub;
  static Timer? _debounceTimer;

  /// Só reavalia janela de datas ao virar o dia civil (sem timer periódico).
  static String? _boundAuthUid;
  static String? _boundFsUid;
  static int? _boundHorizonStartDayMs;

  static void bind(String authUid) {
    if (authUid.trim().isEmpty) {
      unbind();
      return;
    }
    final fsUid = firestoreUserDocIdForAppShell(authUid);
    if (fsUid.isEmpty) {
      unbind();
      return;
    }

    final horizonStartMs = _todayStartMs();
    final alreadyBound = _boundFsUid == fsUid &&
        _scalesSub != null &&
        _remindersSub != null &&
        _boundHorizonStartDayMs == horizonStartMs;
    if (alreadyBound) return;

    unbind();
    _boundAuthUid = authUid.trim();
    _boundFsUid = fsUid;
    _boundHorizonStartDayMs = horizonStartMs;

    final start = DateTime.fromMillisecondsSinceEpoch(horizonStartMs);
    final endDay = start.add(Duration(days: _horizonDays - 1));
    final endInclusive =
        DateTime(endDay.year, endDay.month, endDay.day, 23, 59, 59);

    final scalesQuery = FirebaseFirestore.instance
        .collection('users')
        .doc(fsUid)
        .collection('scales')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endInclusive))
        .limit(_queryLimit);

    final remindersQuery = FirebaseFirestore.instance
        .collection('users')
        .doc(fsUid)
        .collection('reminders')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endInclusive))
        .limit(_queryLimit);

    _scalesSub = scalesQuery.snapshots(includeMetadataChanges: true).listen(
      (snap) => _onLocalChange(snap),
      onError: (Object e, StackTrace st) {
        debugPrint('WidgetFirestoreLiveSync.scales: $e\n$st');
      },
    );

    _remindersSub = remindersQuery.snapshots(includeMetadataChanges: true).listen(
      (snap) => _onLocalChange(snap),
      onError: (Object e, StackTrace st) {
        debugPrint('WidgetFirestoreLiveSync.reminders: $e\n$st');
      },
    );
  }

  /// Reanexa listeners (ex.: app aberto muito tempo / voltou do background).
  static void rebindIfHorizonStale(String authUid) {
    if (authUid.trim().isEmpty) return;
    if (_todayStartMs() != _boundHorizonStartDayMs) {
      bind(authUid);
    }
  }

  static int _todayStartMs() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
  }

  static void _onLocalChange(QuerySnapshot<Map<String, dynamic>> snap) {
    if (snap.docChanges.isEmpty) return;

    final uid = _boundAuthUid;
    if (uid == null || uid.isEmpty) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      WidgetUpdateService.scheduleWidgetRefresh(uid);
    });
  }

  static void unbind() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    unawaited(_scalesSub?.cancel());
    unawaited(_remindersSub?.cancel());
    _scalesSub = null;
    _remindersSub = null;
    _boundAuthUid = null;
    _boundFsUid = null;
    _boundHorizonStartDayMs = null;
  }
}
