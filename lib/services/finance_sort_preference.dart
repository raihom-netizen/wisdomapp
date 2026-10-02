import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/finance_fatura_transaction_sort.dart';
import '../utils/firestore_user_doc_id.dart';

/// Para as telas com grid de lançamentos: começa na ordem gravada, carrega a
/// da conta e atualiza quando o usuário escolhe outra em QUALQUER grid.
///
/// Uma implementação para as cinco grids — cinco cópias dessa lógica é como
/// uma delas esquece de gravar e volta a «esquecer» a ordem.
mixin FinanceSortPreferenceListener<T extends StatefulWidget> on State<T> {
  /// A tela troca a sua ordem (normalmente um `setState`).
  void aoMudarOrdem(FinanceFaturaTxSortMode modo);

  @override
  void initState() {
    super.initState();
    FinanceSortPreference.atual.addListener(_ouvir);
    FinanceSortPreference.carregar(fa.FirebaseAuth.instance.currentUser?.uid ?? '');
  }

  void _ouvir() {
    if (mounted) aoMudarOrdem(FinanceSortPreference.atual.value);
  }

  @override
  void dispose() {
    FinanceSortPreference.atual.removeListener(_ouvir);
    super.dispose();
  }
}

/// A ordem que o usuário escolheu para as grids de lançamentos — UMA só, que
/// vale para todas: Financeiro, tela cheia, ficha do banco (também quando
/// aberta pelo Início) e fatura do cartão.
///
/// Antes cada grid guardava a escolha só na memória e voltava para «mais
/// recente» a cada abertura; o usuário reordenava toda vez.
///
/// Gravada em dois lugares, cada um por um motivo:
///   - no aparelho (SharedPreferences): carrega na hora, sem esperar rede —
///     a grid não pode «pular» de ordem depois de aparecer;
///   - na conta (`settings/finance_prefs.gridSortMode`): quem escolhe no
///     celular encontra a mesma ordem na web.
///
/// Padrão do sistema: data da mais antiga para a mais recente.
abstract final class FinanceSortPreference {
  FinanceSortPreference._();

  static const FinanceFaturaTxSortMode padrao = FinanceFaturaTxSortMode.dateAsc;
  static const String _campo = 'gridSortMode';

  /// A ordem atual. As grids leem daqui e escutam para atualizar quando a
  /// preferência chega da conta.
  static final ValueNotifier<FinanceFaturaTxSortMode> atual = ValueNotifier(padrao);

  static String _chaveLocal(String uid) => 'finance_grid_sort_$uid';

  static String? _carregadoPara;

  /// Carrega a preferência (uma vez por usuário). Primeiro a do aparelho,
  /// depois a da conta — a da conta vence, porque pode ter sido mudada em
  /// outro aparelho.
  static Future<void> carregar(String uid) async {
    final id = firestoreUserDocIdForAppShell(uid);
    if (id.isEmpty || _carregadoPara == id) return;
    _carregadoPara = id;
    try {
      final p = await SharedPreferences.getInstance();
      final local = p.getString(_chaveLocal(id));
      if (local != null) atual.value = FinanceFaturaTxSortModeUi.fromKey(local);
    } catch (_) {
      // Sem armazenamento local (navegador privado): segue para a conta.
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(id)
          .collection('settings')
          .doc('finance_prefs')
          .get();
      final remoto = (snap.data()?[_campo] ?? '').toString();
      if (remoto.isNotEmpty) {
        atual.value = FinanceFaturaTxSortModeUi.fromKey(remoto);
        final p = await SharedPreferences.getInstance();
        await p.setString(_chaveLocal(id), remoto);
      }
    } catch (_) {
      // Offline: fica a do aparelho (ou o padrão).
    }
  }

  /// Grava a escolha e avisa todas as grids abertas.
  static Future<void> definir(String uid, FinanceFaturaTxSortMode modo) async {
    atual.value = modo;
    final id = firestoreUserDocIdForAppShell(uid);
    if (id.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_chaveLocal(id), modo.storageKey);
    } catch (_) {}
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(id)
          .collection('settings')
          .doc('finance_prefs')
          .set({_campo: modo.storageKey, 'updatedAt': FieldValue.serverTimestamp()},
              SetOptions(merge: true));
    } catch (_) {
      // Offline: o Firestore envia quando voltar; a escolha já vale aqui.
    }
  }
}
