import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Blindagem dos carregamentos do Painel Admin: nada de spinner eterno.
///
/// Por que existe (02/10/2026): «Painel Admin · Equipe» ficava carregando para
/// sempre. Duas causas somadas:
///  1. A escuta (`.snapshots()`) era criada DENTRO do build — a cada rebuild
///     (busca, aba, teclado) nascia uma consulta nova; no Firestore Web isso
///     dá `Target ID already exists` / `INTERNAL ASSERTION` e o cliente para
///     de entregar dados (o StreamBuilder fica em «waiting» para sempre).
///  2. Com o faturamento do projeto desligado (01/10 08:06 → 02/10) o SDK Web
///     REPETE a escuta em silêncio — a tela nunca recebe erro.
/// Regra: leitura do admin sempre com prazo; passou do prazo vira erro visível
/// com «Tentar de novo».
class AdminLoadGuard {
  AdminLoadGuard._();

  /// Leitura simples (uma consulta).
  static const Duration curto = Duration(seconds: 20);

  /// Leituras pesadas (milhares de usuários / pagamentos) e callables.
  static const Duration longo = Duration(seconds: 60);

  /// Callables que varrem a base inteira (uso por módulo).
  static const Duration callable = Duration(seconds: 120);

  /// `future` com prazo — estoura [TimeoutException] com mensagem clara.
  static Future<T> comPrazo<T>(
    Future<T> future, {
    Duration prazo = curto,
    String oQue = 'os dados',
  }) {
    return future.timeout(
      prazo,
      onTimeout: () => throw TimeoutException(
        'O servidor não respondeu a tempo ao carregar $oQue.',
        prazo,
      ),
    );
  }

  /// Escuta com prazo só para o PRIMEIRO dado: depois do 1º evento a escuta
  /// segue normal (silêncio entre atualizações é esperado). Se o 1º evento não
  /// chega em [prazo], entrega um erro e encerra — a tela mostra «Tentar de
  /// novo» em vez de girar para sempre.
  ///
  /// Pode ser escutada MAIS DE UMA VEZ (Stream.multi): cada escuta assina a
  /// origem de novo, com o próprio prazo. Antes era um StreamController de
  /// assinatura única guardado no State do AdminScreen — ao sair do módulo e
  /// voltar, o StreamBuilder escutava de novo e dava «Stream has already been
  /// listened to» (02/10/2026).
  static Stream<T> primeiroDadoComPrazo<T>(
    Stream<T> origem, {
    Duration prazo = curto,
    String oQue = 'os dados',
  }) {
    return Stream<T>.multi((ctrl) {
      StreamSubscription<T>? sub;
      Timer? timer;
      var recebeu = false;

      void encerrarComErro(Object e, [StackTrace? st]) {
        timer?.cancel();
        if (ctrl.isClosed) return;
        ctrl.addError(e, st);
        sub?.cancel();
        ctrl.close();
      }

      timer = Timer(prazo, () {
        if (recebeu) return;
        encerrarComErro(TimeoutException(
          'O servidor não respondeu a tempo ao carregar $oQue.',
          prazo,
        ));
      });
      sub = origem.listen(
        (v) {
          recebeu = true;
          timer?.cancel();
          if (!ctrl.isClosed) ctrl.add(v);
        },
        onError: (Object e, StackTrace st) {
          if (!recebeu) {
            encerrarComErro(e, st);
          } else if (!ctrl.isClosed) {
            ctrl.addError(e, st);
          }
        },
        onDone: () {
          timer?.cancel();
          if (!ctrl.isClosed) ctrl.close();
        },
      );
      ctrl.onPause = () => sub?.pause();
      ctrl.onResume = () => sub?.resume();
      ctrl.onCancel = () async {
        timer?.cancel();
        await sub?.cancel();
      };
    });
  }

  /// Mensagem em português, curta e acionável, para qualquer erro de leitura.
  static String mensagem(Object? erro) {
    if (erro == null) return 'Erro desconhecido.';
    final txt = erro.toString();
    final low = txt.toLowerCase();
    if (erro is TimeoutException) {
      return '${erro.message ?? 'O servidor não respondeu a tempo.'} '
          'Confira a internet e toque em «Tentar de novo».';
    }
    if (low.contains('billing')) {
      return 'O faturamento do projeto Firebase está desligado — o servidor '
          'recusa as leituras. Religue o faturamento no Google Cloud e tente de novo.';
    }
    String? code;
    if (erro is FirebaseFunctionsException) code = erro.code;
    if (erro is FirebaseException) code = erro.code;
    code ??= RegExp(r'\[(?:cloud_firestore|firebase_functions)/([a-z-]+)\]')
        .firstMatch(txt)
        ?.group(1);
    switch (code) {
      case 'permission-denied':
        return 'Sem permissão para ler estes dados. Confira se a sua conta '
            'tem papel de administrador; se acabou de mudar, saia e entre de novo.';
      case 'unauthenticated':
        return 'Sessão expirada. Saia e entre de novo no painel.';
      case 'failed-precondition':
        if (low.contains('index')) {
          return 'Falta um índice no Firestore para esta consulta '
              '(publicar firestore.indexes.json). Os dados aparecem sem o filtro '
              'do servidor enquanto isso.';
        }
        if (low.contains('terminated')) {
          return 'A conexão com o banco foi reiniciada. Toque em «Tentar de novo».';
        }
        return 'O servidor recusou a consulta (pré-condição). ${_primeiraLinha(txt)}';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Servidor indisponível ou lento agora. Confira a internet e '
            'toque em «Tentar de novo».';
      case 'resource-exhausted':
        return 'Limite de uso do Firebase atingido no momento. Aguarde alguns '
            'minutos e tente de novo.';
      case 'not-found':
        return 'Função ou documento não encontrado no servidor '
            '(talvez falte publicar as Cloud Functions).';
      case 'internal':
        return 'Erro interno no servidor. ${_primeiraLinha(txt)}';
    }
    if (low.contains('internal assertion') ||
        low.contains('target id already exists') ||
        low.contains('unexpected state')) {
      return 'Instabilidade do Firestore na Web. Toque em «Tentar de novo» '
          '(ou atualize a página).';
    }
    return _primeiraLinha(txt);
  }

  /// O erro pede índice composto (dá para cair no filtro local).
  static bool faltaIndice(Object? erro) {
    final low = (erro ?? '').toString().toLowerCase();
    return low.contains('failed-precondition') && low.contains('index');
  }

  static String _primeiraLinha(String t) {
    final l = t.split('\n').first.trim();
    return l.length > 220 ? '${l.substring(0, 220)}…' : l;
  }
}
