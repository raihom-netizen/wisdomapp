import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart'; // Certifique-se de ter essa lib no pubspec

class ControleFinanceiroScreen extends StatefulWidget {
  const ControleFinanceiroScreen({super.key});
  @override
  State<ControleFinanceiroScreen> createState() => _ControleFinanceiroScreenState();
}

class _ControleFinanceiroScreenState extends State<ControleFinanceiroScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21), // Fundo Dark Moderno
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMainBalance(),
                  const SizedBox(height: 25),
                  _buildActionButtons(),
                  const SizedBox(height: 30),
                  const Text('Fluxo de Caixa', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  _buildChart(),
                  const SizedBox(height: 30),
                  _buildRecentTransactions(),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildAppBar() => SliverAppBar(
    backgroundColor: const Color(0xFF0A0E21),
    expandedHeight: 80,
    floating: true,
    title: const Text('FINANÇAS PRO', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
    actions: [IconButton(icon: const Icon(Icons.account_balance_wallet_outlined), onPressed: () {})],
  );

  Widget _buildMainBalance() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF3949AB)]),
      borderRadius: BorderRadius.circular(30),
      boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Saldo Disponível', style: TextStyle(color: Colors.white70, fontSize: 14)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('R\$ 24.500,80', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
              child: const Text('+12%', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ],
    ),
  );

  Widget _buildActionButtons() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      _actionItem('Receita', Icons.add_chart, Colors.greenAccent),
      _actionItem('Despesa', Icons.analytics, Colors.redAccent),
      _actionItem('Metas', Icons.flag_rounded, Colors.orangeAccent),
    ],
  );

  Widget _actionItem(String t, IconData i, Color c) => Column(
    children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFF1D1E33), borderRadius: BorderRadius.circular(20)),
        child: Icon(i, color: c, size: 28),
      ),
      const SizedBox(height: 8),
      Text(t, style: const TextStyle(color: Colors.white70, fontSize: 12)),
    ],
  );

  Widget _buildChart() => Container(
    height: 180,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: const Color(0xFF1D1E33), borderRadius: BorderRadius.circular(24)),
    child: LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: [const FlSpot(0, 3), const FlSpot(2, 5), const FlSpot(4, 4), const FlSpot(6, 8)],
            isCurved: true, color: Colors.blueAccent, barWidth: 4, dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: Colors.blueAccent.withOpacity(0.1)),
          ),
        ],
      ),
    ),
  );

  Widget _buildRecentTransactions() => Column(
    children: [
      _transactionTile('Mercado Pago', 'R\$ 49,90', 'Hoje', Colors.blue, Icons.payment),
      _transactionTile('Venda Software', 'R\$ 1.200,00', 'Ontem', Colors.green, Icons.arrow_upward),
    ],
  );

  Widget _transactionTile(String t, String v, String d, Color c, IconData i) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: const Color(0xFF1D1E33), borderRadius: BorderRadius.circular(20)),
    child: Row(
      children: [
        CircleAvatar(backgroundColor: c.withOpacity(0.1), child: Icon(i, color: c, size: 20)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          Text(d, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ])),
        Text(v, style: TextStyle(color: c == Colors.green ? Colors.greenAccent : Colors.white, fontWeight: FontWeight.bold)),
      ],
    ),
  );
}
