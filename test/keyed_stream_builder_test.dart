import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:controle_total_premium/widgets/keyed_stream_builder.dart';

/// KeyedStreamBuilder (d58bdb2): mesma chave = mesma escuta; chave nova
/// (ex.: uid vazio → uid do login) = escuta nova que recebe os dados.
void main() {
  Widget host(String key, Stream<String> Function() create, List<String> seen) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: KeyedStreamBuilder<String>(
        streamKey: key,
        create: create,
        builder: (context, snap) {
          if (snap.hasData) seen.add(snap.data!);
          return Text(snap.data ?? 'carregando');
        },
      ),
    );
  }

  testWidgets('rebuild com a mesma chave não recria a escuta',
      (tester) async {
    var creates = 0;
    final ctrl = StreamController<String>.broadcast();
    final seen = <String>[];
    Stream<String> create() {
      creates++;
      return ctrl.stream;
    }

    await tester.pumpWidget(host('users/a', create, seen));
    await tester.pumpWidget(host('users/a', create, seen));
    await tester.pumpWidget(host('users/a', create, seen));
    expect(creates, 1);
    ctrl.add('x');
    await tester.pump();
    await tester.pump();
    expect(find.text('x'), findsOneWidget);
    await ctrl.close();
  });

  testWidgets('chave mudou (uid chegou depois do login) → escuta nova recebe',
      (tester) async {
    final porChave = <String, StreamController<String>>{};
    final seen = <String>[];
    Stream<String> Function() createFor(String k) => () =>
        (porChave[k] = StreamController<String>()).stream;

    // Antes do login: caminho com uid vazio, nunca emite.
    await tester.pumpWidget(host('users/', createFor('users/'), seen));
    expect(find.text('carregando'), findsOneWidget);

    // uid preenchido: tem de assinar o stream novo.
    await tester.pumpWidget(host('users/u1', createFor('users/u1'), seen));
    porChave['users/u1']!.add('dados');
    await tester.pump();
    await tester.pump();
    expect(find.text('dados'), findsOneWidget);
    // A escuta antiga foi cancelada.
    expect(porChave['users/']!.hasListener, isFalse);
  });

  testWidgets('remontar (sair e voltar à tela) recria e recebe de novo',
      (tester) async {
    var creates = 0;
    final seen = <String>[];
    Stream<String> create() {
      creates++;
      return Stream<String>.value('v$creates');
    }

    await tester.pumpWidget(host('k', create, seen));
    await tester.pump();
    expect(find.text('v1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(host('k', create, seen));
    await tester.pump();
    expect(find.text('v2'), findsOneWidget);
  });
}
