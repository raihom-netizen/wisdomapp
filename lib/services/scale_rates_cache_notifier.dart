import 'package:flutter/foundation.dart';

/// Aviso global: parâmetros de hora extra mudaram — Calculadora e plantão recalculam.
class ScaleRatesCacheNotifier extends ChangeNotifier {
  ScaleRatesCacheNotifier._();

  static final ScaleRatesCacheNotifier instance = ScaleRatesCacheNotifier._();

  String? _lastUid;

  String? get lastUid => _lastUid;

  void notifyRatesChanged([String? uid]) {
    _lastUid = uid;
    notifyListeners();
  }
}
