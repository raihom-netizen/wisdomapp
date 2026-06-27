import 'package:cloud_firestore/cloud_firestore.dart';

/// Validade de cursos/dicas (`course_videos`): permanente ou data limite.
class CourseVideoValidity {
  CourseVideoValidity._();

  static const modePermanent = 'permanent';
  static const modeExpires = 'expires';

  static bool isPermanent(Map<String, dynamic> data) {
    final mode = (data['validityMode'] ?? modePermanent).toString().trim();
    if (mode == modePermanent) return true;
    return data['expiresAt'] == null;
  }

  static DateTime? expiresAtDay(Map<String, dynamic> data) {
    final raw = data['expiresAt'];
    if (raw is Timestamp) {
      final d = raw.toDate();
      return DateTime(d.year, d.month, d.day);
    }
    return null;
  }

  static DateTime _todayKey([DateTime? now]) {
    final n = now ?? DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Ainda visível (inclui o último dia da validade).
  static bool isStillValid(Map<String, dynamic> data, [DateTime? now]) {
    if (isPermanent(data)) return true;
    final exp = expiresAtDay(data);
    if (exp == null) return true;
    return !_todayKey(now).isAfter(exp);
  }

  /// Deve ser apagado do banco (dia seguinte ao fim da validade).
  static bool shouldDeleteExpired(Map<String, dynamic> data, [DateTime? now]) {
    if (isPermanent(data)) return false;
    final exp = expiresAtDay(data);
    if (exp == null) return false;
    return _todayKey(now).isAfter(exp);
  }

  static String labelFor(Map<String, dynamic> data) {
    if (isPermanent(data)) return 'Permanente';
    final exp = expiresAtDay(data);
    if (exp == null) return 'Permanente';
    if (shouldDeleteExpired(data)) return 'Expirado';
    final dd = exp.day.toString().padLeft(2, '0');
    final mm = exp.month.toString().padLeft(2, '0');
    return 'Até $dd/$mm/${exp.year}';
  }

  /// Campos Firestore de validade.
  ///
  /// [forUpdate]: true ao editar documento existente (permite `FieldValue.delete`
  /// em `expiresAt` com `set(..., merge: true)`). Na **criação**, omitir o campo.
  static Map<String, dynamic> firestoreFields({
    required bool permanent,
    DateTime? expiresAt,
    bool forUpdate = false,
  }) {
    if (permanent || expiresAt == null) {
      if (forUpdate) {
        return {
          'validityMode': modePermanent,
          'expiresAt': FieldValue.delete(),
        };
      }
      return {'validityMode': modePermanent};
    }
    final end = DateTime(
      expiresAt.year,
      expiresAt.month,
      expiresAt.day,
      23,
      59,
      59,
    );
    return {
      'validityMode': modeExpires,
      'expiresAt': Timestamp.fromDate(end),
    };
  }
}
