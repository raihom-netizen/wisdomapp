import 'package:controle_total_premium/utils/smart_input_voice_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('expandPipeSeparatorsToNewlines: três partes', () {
    final o = SmartInputVoiceText.expandPipeSeparatorsToNewlines(
      'gastei 20 no mercado | 15 reais pão | 8,50 café',
    );
    expect(o.split('\n').length, 3);
    expect(o, contains('gastei 20 no mercado'));
  });

  test('stripBidi: remove bidi invisível', () {
    final t = 'a\u200eb\u200fc';
    final o = SmartInputVoiceText.stripBidiAndControlGarbage(t);
    expect(o.contains(String.fromCharCode(0x200E)), isFalse);
    expect(o.contains('a'), isTrue);
  });

  test('forSmartInputField: pipe vira quebras', () {
    final o = SmartInputVoiceText.forSmartInputField('um | dois | três');
    expect(o.split('\n').length, 3);
  });
}
