import 'package:flutter/material.dart';

class CalculadoraHorasScreen extends StatelessWidget {
  const CalculadoraHorasScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Calculadora')),
        body: Center(child: Text('Horas Extras')),
      );
}
