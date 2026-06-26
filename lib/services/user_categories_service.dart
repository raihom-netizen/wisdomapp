import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/default_categories.dart';
import '../utils/firestore_user_doc_id.dart';

/// Categorias de receita e despesa do usuário: padrão + customizadas (só ele vê).
/// Salvas em users/{uid}/settings/custom_categories. Novos usuários só têm o padrão.
class UserCategoriesService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _ref(String uid) => _db
      .collection('users')
      .doc(firestoreUserDocIdForAppShell(uid))
      .collection('settings')
      .doc('custom_categories');

  /// Carrega listas completas: padrão + customizadas, ordenadas alfabeticamente (pt-BR).
  /// Primeira opção é sempre "Incluir nova" (código especial).
  static const String kIncluirNova = 'Incluir nova';

  /// Chave para ordenação alfabética em português (Água = A, não após Z).
  /// Ordenação alfabética (pt) para listas de categorias (ex.: lançamento expresso, dropdowns).
  static int compareNamesPt(String a, String b) => _sortKeyPt(a).compareTo(_sortKeyPt(b));

  static String _sortKeyPt(String s) {
    const Map<String, String> accents = {
      'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a', 'ä': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'õ': 'o', 'ô': 'o', 'ö': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    return s.toLowerCase().split('').map((c) => accents[c] ?? c).join();
  }

  /// Lista única em ordem A–Z (pt), sem «Incluir nova».
  static List<String> sortedWithoutIncluirNova(Iterable<String> names) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in names) {
      if (raw == kIncluirNova) continue;
      final t = raw.trim();
      if (t.isEmpty) continue;
      final k = t.toLowerCase();
      if (!seen.add(k)) continue;
      out.add(t);
    }
    out.sort(compareNamesPt);
    return out;
  }

  static List<String> _buildVisibleCategoryList({
    required List<String> defaults,
    required List<String> hidden,
    required List<String> custom,
  }) {
    final hiddenLower = hidden.map((e) => e.toLowerCase().trim()).where((e) => e.isNotEmpty).toSet();
    final byKey = <String, String>{};
    void put(String name) {
      final t = name.trim();
      if (t.isEmpty || t == kIncluirNova) return;
      final k = t.toLowerCase();
      byKey.putIfAbsent(k, () => t);
    }
    for (final c in defaults) {
      if (!hiddenLower.contains(c.toLowerCase().trim())) put(c);
    }
    for (final c in custom) {
      put(c);
    }
    final out = byKey.values.toList()..sort(compareNamesPt);
    return out;
  }

  /// Categorias visíveis = padrão (menos as ocultas) + customizadas.
  /// [hiddenDefaultIncome] / [hiddenDefaultExpense] não aparecem nos dropdowns (mas podem ser restauradas).
  Future<({
    List<String> income,
    List<String> expense,
    List<String> hiddenDefaultIncome,
    List<String> hiddenDefaultExpense,
  })> load(String uid) async {
    final snap = await _ref(uid).get();
    final data = snap.data();
    final customIncome = _listFrom(data?['income']);
    final customExpense = _listFrom(data?['expense']);
    final hiddenIncome = _listFrom(data?['hiddenDefaultIncome']);
    final hiddenExpense = _listFrom(data?['hiddenDefaultExpense']);

    final incomeVisible = _buildVisibleCategoryList(
      defaults: kDefaultIncomeCategories,
      hidden: hiddenIncome,
      custom: customIncome,
    );
    final expenseVisible = _buildVisibleCategoryList(
      defaults: kDefaultExpenseCategories,
      hidden: hiddenExpense,
      custom: customExpense,
    );
    final hiddenIncomeSorted = List<String>.from(hiddenIncome)..sort(compareNamesPt);
    final hiddenExpenseSorted = List<String>.from(hiddenExpense)..sort(compareNamesPt);
    return (
      income: [kIncluirNova, ...incomeVisible],
      expense: [kIncluirNova, ...expenseVisible],
      hiddenDefaultIncome: hiddenIncomeSorted,
      hiddenDefaultExpense: hiddenExpenseSorted,
    );
  }

  String? _canonicalDefaultName(String name, bool isIncome) {
    final d = isIncome ? kDefaultIncomeCategories : kDefaultExpenseCategories;
    for (final c in d) {
      if (c.toLowerCase() == name.toLowerCase()) return c;
    }
    return null;
  }

  /// Oculta um nome da lista padrão (não mexe em lançamentos antigos).
  Future<void> hideDefault(String uid, bool isIncome, String name) async {
    final can = _canonicalDefaultName(name, isIncome);
    if (can == null) return;
    final snap = await _ref(uid).get();
    final data = snap.data() ?? <String, dynamic>{};
    final key = isIncome ? 'hiddenDefaultIncome' : 'hiddenDefaultExpense';
    final list = _listFrom(data[key]);
    if (list.any((c) => c.toLowerCase() == can.toLowerCase())) return;
    list.add(can);
    list.sort((a, b) => _sortKeyPt(a).compareTo(_sortKeyPt(b)));
    await _ref(uid).set({
      ...data,
      key: list,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Traz de volta um nome padrão oculto.
  Future<void> unhideDefault(String uid, bool isIncome, String name) async {
    final can = _canonicalDefaultName(name, isIncome);
    if (can == null) return;
    final snap = await _ref(uid).get();
    if (!snap.exists) return;
    final data = snap.data() ?? {};
    final key = isIncome ? 'hiddenDefaultIncome' : 'hiddenDefaultExpense';
    final list = _listFrom(data[key]);
    final out = list.where((c) => c.toLowerCase() != can.toLowerCase()).toList();
    if (out.length == list.length) return;
    await _ref(uid).set({
      ...data,
      key: out,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  List<String> _listFrom(dynamic v) {
    if (v is! List) return [];
    return v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
  }

  /// Adiciona uma categoria customizada (receita ou despesa) para o usuário.
  /// Não duplica. Se o nome coincide com **um padrão ainda visível**, rejeita;
  /// se o padrão com esse nome estiver [oculto](hideDefault), a customização é permitida.
  Future<void> addCustom(String uid, bool isIncome, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == kIncluirNova) return;
    final defaults = isIncome ? kDefaultIncomeCategories : kDefaultExpenseCategories;
    final snap = await _ref(uid).get();
    final data = snap.data() ?? {};
    final hiddenKey = isIncome ? 'hiddenDefaultIncome' : 'hiddenDefaultExpense';
    final hidden = _listFrom(data[hiddenKey]);
    final isHiddenDefault = defaults
        .where((c) => c.toLowerCase() == trimmed.toLowerCase())
        .any((c) => hidden.any((h) => h.toLowerCase() == c.toLowerCase()));
    if (defaults.any((c) => c.toLowerCase() == trimmed.toLowerCase()) && !isHiddenDefault) {
      return;
    }
    final key = isIncome ? 'income' : 'expense';
    final current = _listFrom(data[key]);
    if (current.any((c) => c.toLowerCase() == trimmed.toLowerCase())) return;

    current.add(trimmed);
    current.sort((a, b) => _sortKeyPt(a).compareTo(_sortKeyPt(b)));
    final payload = <String, dynamic>{
      key: current,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (snap.exists) {
      await _ref(uid).update(payload);
    } else {
      final otherKey = isIncome ? 'expense' : 'income';
      payload[otherKey] = [];
      await _ref(uid).set(payload);
    }
  }

  /// Remove categoria customizada (não remove as padrão).
  Future<void> removeCustom(String uid, bool isIncome, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final defaults = isIncome ? kDefaultIncomeCategories : kDefaultExpenseCategories;
    if (defaults.any((c) => c.toLowerCase() == trimmed.toLowerCase())) return;

    final snap = await _ref(uid).get();
    final data = snap.data() ?? {};
    final key = isIncome ? 'income' : 'expense';
    final current = _listFrom(data[key]);
    final updated = current.where((c) => c.toLowerCase() != trimmed.toLowerCase()).toList();
    if (updated.length == current.length) return;

    await _ref(uid).set({
      ...data,
      key: updated,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Renomeia categoria customizada. Padrão do app: use [hideDefault] + [addCustom].
  Future<void> renameCustom(String uid, bool isIncome, String oldName, String newName) async {
    final o = oldName.trim();
    final t = newName.trim();
    if (o.isEmpty || t.isEmpty || t == kIncluirNova) return;
    if (o.toLowerCase() == t.toLowerCase()) return;
    final defaults = isIncome ? kDefaultIncomeCategories : kDefaultExpenseCategories;
    if (defaults.any((c) => c.toLowerCase() == t.toLowerCase())) return;
    if (defaults.any((c) => c.toLowerCase() == o.toLowerCase())) return;
    final snap = await _ref(uid).get();
    final data = snap.data() ?? {};
    final key = isIncome ? 'income' : 'expense';
    final current = _listFrom(data[key]);
    if (!current.any((c) => c.toLowerCase() == o.toLowerCase())) return;
    if (current.any((c) => c != o && c.toLowerCase() == t.toLowerCase())) return;

    final next = current.map((c) => c.toLowerCase() == o.toLowerCase() ? t : c).toList();
    next.sort((a, b) => _sortKeyPt(a).compareTo(_sortKeyPt(b)));
    await _ref(uid).set({
      ...data,
      key: next,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
