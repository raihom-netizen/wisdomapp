import 'package:controle_total_premium/constants/commitment_symbols.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catálogo de emojis tem ao menos 200 itens únicos', () {
    final todos = <String>{
      for (final g in kCommitmentEmojiGroups) ...g.emojis,
    };
    expect(todos.length, greaterThanOrEqualTo(200));
  });

  test('toda chave de ícone dos grupos existe e todo ícone aparece num grupo', () {
    final nosGrupos = <String>{
      for (final g in kCommitmentIconGroups)
        for (final e in g.itens) e.key,
    };
    for (final k in nosGrupos) {
      expect(kCommitmentIcons.containsKey(k), isTrue, reason: k);
    }
    for (final k in kCommitmentIcons.keys) {
      expect(nosGrupos.contains(k), isTrue, reason: k);
    }
  });

  test('formato gravado não mudou (emoji:/icon:) e chaves antigas seguem válidas', () {
    expect(const CommitmentSymbol.emoji('🎂').raw, 'emoji:🎂');
    expect(CommitmentSymbol.parse('icon:medical')?.iconKey, 'medical');
    for (final k in const [
      'cake', 'celebration', 'favorite', 'medical', 'work', 'church', 'lightbulb',
    ]) {
      expect(kCommitmentIcons.containsKey(k), isTrue, reason: k);
    }
  });

  test('busca ignora acentos', () {
    expect(commitmentSearchNormalize('Aniversário Ç'), 'aniversario c');
  });
}
