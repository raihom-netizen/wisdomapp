import 'package:flutter/material.dart';
import 'fast_text_field.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PainelNotificacoes extends StatefulWidget {
  const PainelNotificacoes({super.key});
  @override
  State<PainelNotificacoes> createState() => _PainelNotificacoesState();
}

class _PainelNotificacoesState extends State<PainelNotificacoes> {
  final _tituloCtrl = TextEditingController();
  final _mensagemCtrl = TextEditingController();
  bool _enviando = false;

  Future<void> _dispararNotificacao() async {
    setState(() => _enviando = true);
    try {
      // Cria um documento na coleção 'notifications' para disparar via Cloud Functions
      await FirebaseFirestore.instance.collection('notifications').add({
        'title': _tituloCtrl.text,
        'body': _mensagemCtrl.text,
        'scheduledTime': FieldValue.serverTimestamp(),
        'status': 'pending',
        'target': 'all', // Pode ser alterado para filtros específicos
      });
      
      _tituloCtrl.clear();
      _mensagemCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🚀 Notificação enviada para a fila de disparo!')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Erro ao disparar: $e')));
    } finally {
      setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: const Color(0xFF1D1E33), borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('NOTIFICAÇÕES PUSH', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _buildField('Título do Aviso', _tituloCtrl),
          const SizedBox(height: 15),
          _buildField('Mensagem Completa', _mensagemCtrl, maxLines: 3),
          const SizedBox(height: 25),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _enviando ? null : _dispararNotificacao,
              icon: const Icon(Icons.send, color: Colors.white),
              label: Text(_enviando ? 'ENVIANDO...' : 'DISPARAR PARA TODOS', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, {int maxLines = 1}) {
    return FastTextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: Colors.black26,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    );
  }
}
