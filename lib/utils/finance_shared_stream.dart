import 'dart:async';

/// Uma escuta só, repartida entre todas as telas que pedem o mesmo dado.
///
/// Telas que montam `StreamBuilder(stream: servico.stream(uid))` dentro do
/// `build` criavam uma escuta NOVA no Firestore a cada redesenho (e o
/// carrossel do Início/Financeiro redesenha muito). Com este cache o serviço
/// devolve SEMPRE a mesma instância de [Stream] para a mesma chave:
/// - o StreamBuilder não reinscreve (mesmo objeto entre builds);
/// - quem entra depois recebe na hora o último valor (sem esqueleto);
/// - a escuta real só fecha uns segundos depois do último ouvinte sair
///   (troca de aba não derruba e reabre a escuta).
class FinanceSharedStream<T> {
  FinanceSharedStream(this._open, {this.linger = const Duration(seconds: 20)});

  final Stream<T> Function() _open;
  final Duration linger;

  final Set<MultiStreamController<T>> _listeners = {};
  StreamSubscription<T>? _upstream;
  Timer? _closeTimer;
  T? _last;
  bool _hasLast = false;
  // Último erro sem valor depois: quem chega depois também vê o erro (e a
  // tela mostra «Tentar de novo») em vez de ficar esperando para sempre.
  Object? _lastError;
  StackTrace? _lastErrorSt;

  /// Último valor recebido (se houver).
  T? get last => _hasLast ? _last : null;

  late final Stream<T> stream = Stream<T>.multi((c) {
    _closeTimer?.cancel();
    _closeTimer = null;
    _listeners.add(c);
    if (_hasLast) {
      c.add(_last as T);
    } else if (_lastError != null) {
      c.addError(_lastError!, _lastErrorSt);
    }
    _upstream ??= _open().listen(
      (v) {
        _last = v;
        _hasLast = true;
        _lastError = null;
        _lastErrorSt = null;
        for (final l in List.of(_listeners)) {
          l.add(v);
        }
      },
      onError: (Object e, StackTrace st) {
        if (!_hasLast) {
          _lastError = e;
          _lastErrorSt = st;
        }
        for (final l in List.of(_listeners)) {
          l.addError(e, st);
        }
      },
      onDone: () {
        // A escuta do Firestore terminou (erro de permissão, sessão trocada):
        // o próximo ouvinte abre outra.
        _upstream = null;
      },
    );
    c.onCancel = () {
      _listeners.remove(c);
      if (_listeners.isEmpty) {
        _closeTimer?.cancel();
        _closeTimer = Timer(linger, () {
          if (_listeners.isNotEmpty) return;
          _upstream?.cancel();
          _upstream = null;
        });
      }
    };
  });
}

/// Cache de [FinanceSharedStream] por chave (normalmente o uid).
class FinanceSharedStreamCache<T> {
  final Map<String, FinanceSharedStream<T>> _byKey = {};

  FinanceSharedStream<T> obter(String key, Stream<T> Function() open) =>
      _byKey.putIfAbsent(key, () => FinanceSharedStream<T>(open));

  /// Último valor da escuta desta chave (sem abrir escuta nova).
  T? peek(String key) => _byKey[key]?.last;

  /// Esquece a escuta desta chave: o próximo [obter] abre uma nova («Tentar de
  /// novo» depois de erro). Quem ainda ouve a antiga continua até sair.
  void descartar(String key) => _byKey.remove(key);
}
