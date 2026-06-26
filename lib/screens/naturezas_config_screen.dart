import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import '../constants/default_ocorrencias_naturezas.dart';
import '../services/ocorrencias_naturezas_service.dart';
import '../theme/app_colors.dart';

/// Tela em Configurações para gerenciar naturezas de ocorrência (produtividade).
class NaturezasConfigScreen extends StatefulWidget {
  final String uid;

  const NaturezasConfigScreen({super.key, required this.uid});

  @override
  State<NaturezasConfigScreen> createState() => _NaturezasConfigScreenState();
}

class _NaturezasConfigScreenState extends State<NaturezasConfigScreen> {
  final _service = OcorrenciasNaturezasService();
  List<OcorrenciaNatureza> _naturezas = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _service.load(widget.uid);
    if (mounted) setState(() {
      _naturezas = list;
      _loading = false;
    });
  }

  Future<void> _addNatureza() async {
    final labelCtrl = TextEditingController();
    final pontosCtrl = TextEditingController(text: '2');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nova natureza'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FastTextField(
              controller: labelCtrl,
              decoration: const InputDecoration(
                labelText: 'Descrição',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FastTextField(
              controller: pontosCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Pontuação',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (labelCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final label = labelCtrl.text.trim();
    final pontos = int.tryParse(pontosCtrl.text) ?? 2;
    await _service.add(widget.uid, label, pontos);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Natureza adicionada.')));
      _load();
    }
  }

  Future<void> _editNatureza(OcorrenciaNatureza n) async {
    final labelCtrl = TextEditingController(text: n.label);
    final pontosCtrl = TextEditingController(text: n.pontos.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar natureza'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FastTextField(
              controller: labelCtrl,
              decoration: const InputDecoration(labelText: 'Descrição', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            FastTextField(
              controller: pontosCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Pontuação', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final label = labelCtrl.text.trim();
              if (label.isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final label = labelCtrl.text.trim();
    final pontos = int.tryParse(pontosCtrl.text) ?? n.pontos;
    await _service.update(widget.uid, OcorrenciaNatureza(id: n.id, label: label.isEmpty ? n.label : label, pontos: pontos));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Natureza atualizada.')));
      _load();
    }
  }

  Future<void> _removeNatureza(OcorrenciaNatureza n) async {
    final isPadrao = int.tryParse(n.id) != null && int.parse(n.id) >= 1 && int.parse(n.id) <= 7;
    if (isPadrao) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Naturezas padrão não podem ser removidas.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remover?'),
        content: Text('Remover "${n.label}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(_, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _service.remove(widget.uid, n.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Natureza removida.')));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Naturezas de Ocorrência'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: _loading ? null : _addNatureza,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 24, color: Colors.amber.shade800),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Naturezas definem tipos de ocorrência e pontuação. Ao atingir a pontuação configurada em "Pontuação para folga", você pode marcar sua folga.',
                          style: TextStyle(fontSize: 13, color: Colors.amber.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ..._naturezas.map((n) {
                  final isPadrao = int.tryParse(n.id) != null && int.parse(n.id) >= 1 && int.parse(n.id) <= 7;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: ListTile(
                      title: Text(n.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${n.pontos} pontos'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 22),
                            onPressed: () => _editNatureza(n),
                          ),
                          if (!isPadrao)
                            IconButton(
                              icon: Icon(Icons.delete_outline_rounded, size: 22, color: AppColors.error),
                              onPressed: () => _removeNatureza(n),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
        ),
    );
  }
}
