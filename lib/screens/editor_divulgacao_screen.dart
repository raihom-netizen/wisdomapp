import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditorDivulgacaoScreen extends StatefulWidget {
  const EditorDivulgacaoScreen({super.key});
  @override
  State<EditorDivulgacaoScreen> createState() => _EditorDivulgacaoScreenState();
}

class _EditorDivulgacaoScreenState extends State<EditorDivulgacaoScreen> {
  final _tituloCtrl = TextEditingController();
  final _subtituloCtrl = TextEditingController();
  final _urlBannerCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _carregarDadosAtuais();
  }

  Future<void> _carregarDadosAtuais() async {
    var doc = await FirebaseFirestore.instance.collection('settings').doc('landing_page').get();
    if (doc.exists) {
      setState(() {
        _tituloCtrl.text = doc.data()?['titulo'] ?? '';
        _subtituloCtrl.text = doc.data()?['subtitulo'] ?? '';
        _urlBannerCtrl.text = doc.data()?['urlBanner'] ?? '';
      });
    }
  }

  Future<void> _salvarAlteracoes() async {
    setState(() => _isSaving = true);
    await FirebaseFirestore.instance.collection('settings').doc('landing_page').set({
      'titulo': _tituloCtrl.text,
      'subtitulo': _subtituloCtrl.text,
      'urlBanner': _urlBannerCtrl.text,
      'lastUpdate': FieldValue.serverTimestamp(),
    });
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Site Atualizado com Sucesso!')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Voltar',
        ),
        title: const Text('EDITOR DE SITE'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
          children: [
            _buildField('Título Principal', _tituloCtrl),
            const SizedBox(height: 20),
            _buildField('Subtítulo / Descrição', _subtituloCtrl, maxLines: 3),
            const SizedBox(height: 20),
            _buildField('URL da Imagem de Banner', _urlBannerCtrl),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _salvarAlteracoes,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: _isSaving ? const CircularProgressIndicator() : const Text('PUBLICAR ALTERAÇÕES', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ],
        ),
        ),
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
        fillColor: const Color(0xFF1D1E33),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    );
  }
}
