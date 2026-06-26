import 'package:cloud_firestore/cloud_firestore.dart';

bool _isFirestoreTransient(Object e) {
  if (e is FirebaseException) {
    const codes = {
      'unavailable',
      'deadline-exceeded',
      'resource-exhausted',
      'aborted',
    };
    return codes.contains(e.code);
  }
  final s = e.toString().toLowerCase();
  if (s.contains('internal assertion') ||
      s.contains('unexpected state') ||
      s.contains('watchchangeaggregator') ||
      s.contains('persistentlistenstream')) {
    return true;
  }
  return s.contains('unavailable') ||
      s.contains('deadline-exceeded') ||
      s.contains('network_error');
}

/// Repete leituras quando o Firestore devolve erro transitório (rede instável, sobrecarga).
Future<T> runFirestoreWithRetry<T>(
  Future<T> Function() fn, {
  int maxAttempts = 5,
  Duration initialDelay = const Duration(milliseconds: 350),
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (e, st) {
      final retry = _isFirestoreTransient(e) && attempt < maxAttempts - 1;
      if (!retry) {
        Error.throwWithStackTrace(e, st);
      }
      await Future<void>.delayed(initialDelay * (1 << attempt));
    }
  }
  throw StateError('firestore_retry: exhausted attempts');
}
