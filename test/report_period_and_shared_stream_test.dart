import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:controle_total_premium/utils/finance_shared_stream.dart';
import 'package:controle_total_premium/utils/report_period_loader.dart';

void main() {
  group('reportMonthChunks', () {
    test('ano inteiro vira 12 faixas mensais sem buraco', () {
      final c = reportMonthChunks(DateTime(2026, 1, 1), DateTime(2026, 12, 31));
      expect(c.length, 12);
      expect(c.first.$1, DateTime(2026, 1, 1));
      expect(c.last.$2, DateTime(2027, 1, 1));
      for (var i = 1; i < c.length; i++) {
        expect(c[i].$1, c[i - 1].$2);
      }
    });

    test('período no meio do mês respeita início e fim', () {
      final c = reportMonthChunks(DateTime(2026, 10, 15), DateTime(2026, 11, 3));
      expect(c, [
        (DateTime(2026, 10, 15), DateTime(2026, 11, 1)),
        (DateTime(2026, 11, 1), DateTime(2026, 11, 4)),
      ]);
    });
  });

  group('FinanceSharedStream', () {
    test('uma escuta só e quem chega depois recebe o último valor', () async {
      var aberturas = 0;
      final ctrl = StreamController<int>.broadcast();
      final shared = FinanceSharedStream<int>(() {
        aberturas++;
        return ctrl.stream;
      }, linger: Duration.zero);
      final a = <int>[];
      final sa = shared.stream.listen(a.add);
      await Future<void>.delayed(Duration.zero);
      ctrl.add(1);
      await Future<void>.delayed(Duration.zero);
      final b = <int>[];
      final sb = shared.stream.listen(b.add);
      await Future<void>.delayed(Duration.zero);
      expect(aberturas, 1);
      expect(a, [1]);
      expect(b, [1]);
      await sa.cancel();
      await sb.cancel();
      await ctrl.close();
    });

    test('erro sem valor chega também a quem entra depois', () async {
      final ctrl = StreamController<int>.broadcast();
      final shared = FinanceSharedStream<int>(() => ctrl.stream, linger: Duration.zero);
      final s1 = shared.stream.listen((_) {}, onError: (_) {});
      await Future<void>.delayed(Duration.zero);
      ctrl.addError(StateError('x'));
      await Future<void>.delayed(Duration.zero);
      Object? erro;
      final s2 = shared.stream.listen((_) {}, onError: (Object e) => erro = e);
      await Future<void>.delayed(Duration.zero);
      expect(erro, isA<StateError>());
      await s1.cancel();
      await s2.cancel();
      await ctrl.close();
    });
  });
}
