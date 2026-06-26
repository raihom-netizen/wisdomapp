import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CpfAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String normalizeCpf(String cpf) => cpf.replaceAll(RegExp(r'[^0-9]'), '');

  Future<String> cpfToEmail(String cpfOrEmail) async {
    final input = cpfOrEmail.trim();
    if (input.contains('@')) return input; // permite e-mail para admin/teste
    final cpf = normalizeCpf(input);
    if (cpf.length != 11) throw Exception('CPF inválido');

    final doc = await _db.collection('cpf_index').doc(cpf).get();
    final data = doc.data();
    if (data == null || (data['email'] ?? '').toString().isEmpty) {
      throw Exception('CPF não cadastrado');
    }
    return data['email'].toString();
  }

  Future<UserCredential> signInWithCpf({required String cpfOrEmail, required String password}) async {
    final email = await cpfToEmail(cpfOrEmail);
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> resetPasswordByCpf(String cpfOrEmail) async {
    final email = await cpfToEmail(cpfOrEmail);
    await _auth.sendPasswordResetEmail(email: email);
  }
}
