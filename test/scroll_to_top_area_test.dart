import 'package:controle_total_premium/widgets/shell_scroll_to_top_fab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('botão voltar ao topo aparece após rolar e volta ao topo',
      (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScrollToTopArea(
            child: ListView.builder(
              controller: controller,
              itemCount: 200,
              itemBuilder: (_, i) =>
                  SizedBox(height: 50, child: Text('Item $i')),
            ),
          ),
        ),
      ),
    );

    ScrollToTopButton btn() =>
        tester.widget<ScrollToTopButton>(find.byType(ScrollToTopButton));
    expect(btn().visible, isFalse);

    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(btn().visible, isTrue);
    expect(controller.offset, greaterThan(100));

    await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    expect(btn().visible, isFalse);
  });
}
