import 'package:flutter/material.dart';

class PlanejamentoFinanceiroScreen extends StatelessWidget {
  const PlanejamentoFinanceiroScreen({super.key});

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
        title: const Text('MetaFinance'),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
          children: [
            _cardObjetivo(),
            const SizedBox(height: 25),
            _resumoFinanceiro(),
          ],
        ),
        ),
      ),
    );
  }

  Widget _cardObjetivo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(colors: [Color(0xFF1A237E), Colors.black87]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Objetivo: Viagem dos Sonhos!', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          LinearProgressIndicator(value: 0.6, backgroundColor: Colors.white12, color: Colors.blueAccent, minHeight: 8),
          const SizedBox(height: 10),
          const Text('R\$ 18.200 / R\$ 30.000', style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _resumoFinanceiro() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFF1D1E33), borderRadius: BorderRadius.circular(24)),
      child: const Column(
        children: [
          Text('Saldo Atual', style: TextStyle(color: Colors.white70)),
          Text('R\$ 12.580', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
