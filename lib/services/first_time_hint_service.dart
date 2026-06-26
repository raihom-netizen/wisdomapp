import 'package:shared_preferences/shared_preferences.dart';

/// Chave para indicar que a dica da primeira vez nos sheets foi mostrada.
const String _keySheetSelectionHintShown = 'sheet_selection_hint_shown';

/// Verifica se deve mostrar a dica única de "Selecionar para excluir em lote".
/// Mostra só na primeira abertura de qualquer um dos sheets (Despesas pendentes, Receitas pendentes etc.).
Future<bool> shouldShowSheetSelectionHint() async {
  final prefs = await SharedPreferences.getInstance();
  return !(prefs.getBool(_keySheetSelectionHintShown) ?? false);
}

/// Marca que a dica já foi mostrada (não exibir novamente).
Future<void> markSheetSelectionHintShown() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_keySheetSelectionHintShown, true);
}
