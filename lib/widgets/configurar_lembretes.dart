import 'package:flutter/material.dart';
import 'fast_text_field.dart';

/// Converte tempo + unidade para minutos (antecedência).
int reminderToMinutes(int tempo, String unidade) {
  switch (unidade) {
    case 'Dias':
      return tempo * 24 * 60;
    case 'Horas':
      return tempo * 60;
    case 'Minutos':
    default:
      return tempo;
  }
}

/// Widget de configuração de lembretes de plantão: padrões (1 dia, 1 hora) + avisos personalizados.
/// Usado no formulário de criação de plantão. Os avisos são enviados via flutter_local_notifications.
class ConfigurarLembretes extends StatefulWidget {
  /// Lista inicial de lembretes. Cada item: {'tempo': int, 'unidade': String, 'label': String}.
  final List<Map<String, dynamic>>? initial;
  /// Chamado quando a lista de lembretes mudar. Útil para o pai obter reminderLeads em minutos.
  final void Function(List<Map<String, dynamic>>)? onChanged;

  const ConfigurarLembretes({super.key, this.initial, this.onChanged});

  @override
  State<ConfigurarLembretes> createState() => _ConfigurarLembretesState();
}

class _ConfigurarLembretesState extends State<ConfigurarLembretes> {
  late List<Map<String, dynamic>> lembretes;

  @override
  void initState() {
    super.initState();
    lembretes = widget.initial != null
        ? List<Map<String, dynamic>>.from(widget.initial!.map((e) => Map<String, dynamic>.from(e)))
        : [
            {'tempo': 1, 'unidade': 'Dias', 'label': '1 dia antes'},
            {'tempo': 1, 'unidade': 'Horas', 'label': '1 hora antes'},
          ];
  }

  void _notifyChanged() {
    widget.onChanged?.call(List<Map<String, dynamic>>.from(lembretes.map((e) => Map<String, dynamic>.from(e))));
  }

  void _adicionarLembretePersonalizado() {
    int tempo = 30;
    String unidade = 'Minutos';
    final tempoCtrl = TextEditingController(text: '30');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Novo aviso'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FastTextField(
                  controller: tempoCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Tempo',
                    hintText: 'Ex: 30',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) {
                    final v = int.tryParse(val.trim());
                    if (v != null && v > 0) setDialogState(() => tempo = v);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: unidade,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: ['Minutos', 'Horas', 'Dias'].map((String value) {
                    return DropdownMenuItem<String>(value: value, child: Text(value));
                  }).toList(),
                  onChanged: (val) => setDialogState(() => unidade = val ?? 'Minutos'),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: () {
                  String label;
                  if (unidade == 'Dias') label = '$tempo dia(s) antes';
                  else if (unidade == 'Horas') label = '$tempo hora(s) antes';
                  else label = '$tempo min antes';
                  setState(() {
                    lembretes.add({
                      'tempo': tempo,
                      'unidade': unidade,
                      'label': label,
                    });
                    _notifyChanged();
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Adicionar'),
              ),
            ],
          );
        },
      ),
    ).whenComplete(tempoCtrl.dispose);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.notifications_active_outlined, color: Color(0xFF1A237E), size: 22),
            SizedBox(width: 10),
            Text(
              'Lembretes de plantão',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: lembretes.map((l) {
            final label = (l['label'] ?? '${l['tempo']} ${l['unidade']} antes').toString();
            return Chip(
              backgroundColor: Colors.blue.shade50,
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: () {
                setState(() {
                  lembretes.remove(l);
                  _notifyChanged();
                });
              },
              label: Text(label, style: const TextStyle(fontSize: 12)),
            );
          }).toList(),
        ),
        TextButton.icon(
          onPressed: _adicionarLembretePersonalizado,
          icon: const Icon(Icons.add_circle_outline, size: 20),
          label: const Text('Personalizar outro aviso'),
        ),
      ],
    );
  }
}
