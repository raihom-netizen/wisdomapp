import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/currency_formats.dart';

class CalculadoraPage extends StatefulWidget {
  const CalculadoraPage({super.key});

  @override
  State<CalculadoraPage> createState() => _CalculadoraPageState();
}

class _CalculadoraPageState extends State<CalculadoraPage> {
  final _horasController = TextEditingController(text: "12");
  double _valorHoraGoiass = 0.0;
  double _resultado = 0.0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _buscarValoresAdmin();
  }

  // Busca os valores de hora definidos pelo ADM no Firestore
  Future<void> _buscarValoresAdmin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      // Puxa a configuração de taxas (rates) do estado de Goiás definida no Painel
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('rates')
          .get();

      if (doc.exists) {
        setState(() {
          // Pega o valor diurno padrão (ex: segunda-feira) definido pelo admin
          _valorHoraGoiass = (doc.data()?['valueDiurno'] as List)[0].toDouble();
          _loading = false;
        });
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _calcular() {
    double horas = double.tryParse(_horasController.text) ?? 0;
    setState(() => _resultado = horas * _valorHoraGoiass);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Voltar',
              )
            : null,
        title: const Text('Calculadora Goiás'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _visorResultado(),
                const SizedBox(height: 30),
                _campoInput("Horas de Plantão", _horasController),
                const SizedBox(height: 20),
                Text("Valor da Hora (ADM): ${CurrencyFormats.formatBRL(_valorHoraGoiass)}", 
                  style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                const Spacer(),
                _botaoCalcular(),
              ],
            ),
          ),
        ),
    );
  }

  Widget _visorResultado() => Container(
    width: double.infinity, padding: const EdgeInsets.all(30),
    decoration: BoxDecoration(color: const Color(0xFF1D1E33), borderRadius: BorderRadius.circular(24)),
    child: Column(children: [
      const Text('GANHO ESTIMADO', style: TextStyle(color: Colors.white70, fontSize: 12)),
      Text(CurrencyFormats.formatBRL(_resultado), style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900)),
    ]),
  );

  Widget _campoInput(String label, TextEditingController ctrl) => FastTextField(
    controller: ctrl, keyboardType: TextInputType.number,
    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    decoration: InputDecoration(
      labelText: label, labelStyle: const TextStyle(color: Colors.white60),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.white12)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.blueAccent)),
    ),
  );

  Widget _botaoCalcular() => SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: _calcular,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blueAccent, padding: const EdgeInsets.symmetric(vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      child: const Text('CALCULAR AGORA', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
    ),
  );
}
