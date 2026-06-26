import 'package:flutter/material.dart';

import '../constants/currency_formats.dart';
import '../models/scale_rates.dart';
import '../widgets/brl_amount_text_field.dart';
import '../services/logs_service.dart';
import '../services/scale_rates_service.dart';

/// Tela para o usuário personalizar valores padrão de hora diurna/noturna por dia da semana.
/// Base: AC4 Goiás. Os valores são usados no cálculo automático dos plantões.
class ScaleRatesEditScreen extends StatefulWidget {
  final String uid;

  const ScaleRatesEditScreen({super.key, required this.uid});

  @override
  State<ScaleRatesEditScreen> createState() => _ScaleRatesEditScreenState();
}

class _ScaleRatesEditScreenState extends State<ScaleRatesEditScreen> {
  static const _weekdayLabels = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'];
  late List<TextEditingController> _diurnoControllers;
  late List<TextEditingController> _noturnoControllers;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _diurnoControllers = List.generate(7, (_) => TextEditingController());
    _noturnoControllers = List.generate(7, (_) => TextEditingController());
    _loadRates();
  }

  @override
  void dispose() {
    for (final c in _diurnoControllers) {
      c.dispose();
    }
    for (final c in _noturnoControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadRates() async {
    final rates = await ScaleRatesService().getRates(uid: widget.uid);
    if (!mounted) return;
    for (int i = 0; i < 7; i++) {
      _diurnoControllers[i].text = CurrencyFormats.formatBRLInput(rates.valueDiurno[i]);
      _noturnoControllers[i].text = CurrencyFormats.formatBRLInput(rates.valueNoturno[i]);
    }
    setState(() => _loading = false);
  }

  ScaleRates _ratesFromControllers() {
    double parse(TextEditingController c) =>
        CurrencyFormats.parseBRLInput(c.text) ?? 0;
    return ScaleRates(
      valueDiurno: _diurnoControllers.map((c) => parse(c)).toList(),
      valueNoturno: _noturnoControllers.map((c) => parse(c)).toList(),
    );
  }

  void _applyRates(ScaleRates rates) {
    for (int i = 0; i < 7; i++) {
      _diurnoControllers[i].text = CurrencyFormats.formatBRLInput(rates.valueDiurno[i]);
      _noturnoControllers[i].text = CurrencyFormats.formatBRLInput(rates.valueNoturno[i]);
    }
    setState(() {});
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ScaleRatesService().setUserRates(widget.uid, _ratesFromControllers());
      ScaleRatesService().invalidateMemory(widget.uid);
      await LogsService().saveLog(
        modulo: 'Escalas',
        acao: 'Atualizou valores da hora extra',
        detalhes: 'Personalização de diurno/noturno salva',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valores salvos. Os cálculos usarão sua personalização.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Voltar',
        ),
        title: const Text('Valor da hora extra'),
        actions: [
          if (!_loading)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Salvar'),
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Valores de hora diurna e noturna por dia da semana. Base: AC4 (Goiás). Personalize conforme sua realidade.',
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: () => _applyRates(ScaleRates.defaultRates),
                            icon: const Icon(Icons.restore_rounded, size: 20),
                            label: const Text('Restaurar padrão Goiás (AC4)'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Table(
                    columnWidths: const {
                      0: FlexColumnWidth(1.2),
                      1: FlexColumnWidth(1),
                      2: FlexColumnWidth(1),
                    },
                    children: [
                      TableRow(
                        decoration: BoxDecoration(color: Colors.grey.shade200),
                        children: [
                          Padding(padding: const EdgeInsets.all(8), child: Text('Dia', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey.shade800))),
                          Padding(padding: const EdgeInsets.all(8), child: Text('Diurno (R\$)', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey.shade800))),
                          Padding(padding: const EdgeInsets.all(8), child: Text('Noturno (R\$)', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey.shade800))),
                        ],
                      ),
                      ...List.generate(7, (i) => TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(_weekdayLabels[i], style: const TextStyle(fontWeight: FontWeight.w500)),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: BrlAmountTextField(
                              controller: _diurnoControllers[i],
                              useNativeAndroidKeypad: false,
                              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: BrlAmountTextField(
                              controller: _noturnoControllers[i],
                              useNativeAndroidKeypad: false,
                              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      )),
                    ],
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded),
                    label: Text(_saving ? 'Salvando...' : 'Salvar minha personalização'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFF2D5BFF),
                    ),
                  ),
                ],
              ),
            ),
        ),
    );
  }
}
