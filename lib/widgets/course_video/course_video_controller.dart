import 'package:flutter/foundation.dart';

/// O que o embed (WebView no celular, iframe/`<video>` na web) sabe fazer.
abstract class CourseVideoCommandTarget {
  Future<void> pause();
  Future<void> setPlaybackRate(double rate);
}

/// Comandos para o player de curso a partir da tela (velocidade, pausar) e a
/// última posição informada pelo player (para abrir a tela cheia no ponto).
///
/// A velocidade escolhida fica guardada: quando um embed novo se conecta
/// (ex.: voltou da tela cheia), ela é reaplicada.
class CourseVideoController extends ChangeNotifier {
  CourseVideoCommandTarget? _target;
  double _rate = 1.0;
  double _position = 0;
  double _duration = 0;

  double get playbackRate => _rate;
  double get position => _position;
  double get duration => _duration;
  bool get hasTarget => _target != null;

  void attach(CourseVideoCommandTarget target) {
    _target = target;
  }

  void detach(CourseVideoCommandTarget target) {
    if (identical(_target, target)) _target = null;
  }

  Future<void> pause() async {
    try {
      await _target?.pause();
    } catch (_) {}
  }

  Future<void> setPlaybackRate(double rate) async {
    if (rate <= 0) return;
    if (_rate != rate) {
      _rate = rate;
      notifyListeners();
    }
    try {
      await _target?.setPlaybackRate(rate);
    } catch (_) {}
  }

  /// Chamado pelo embed quando o player fica pronto — reaplica a velocidade.
  Future<void> reapplyTo(CourseVideoCommandTarget target) async {
    if (_rate == 1.0) return;
    try {
      await target.setPlaybackRate(_rate);
    } catch (_) {}
  }

  void reportProgress(double position, double duration) {
    if (position.isFinite && position >= 0) _position = position;
    if (duration.isFinite && duration > 0) _duration = duration;
  }
}
