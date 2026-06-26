import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SuperAdminHome extends StatefulWidget {
  const SuperAdminHome({super.key});
  @override
  State<SuperAdminHome> createState() => _SuperAdminHomeState();
}

class _SuperAdminHomeState extends State<SuperAdminHome> {
  // Configuração do Google Drive com o seu ID Raiz
  final _folderIdCtrl = TextEditingController(text: "1fMXYKu7Pz934L4ElZnHWdldJHfaPJKqd");
  final _backupFrequencyCtrl = TextEditingController(text: "Diário (23:00)");
  
  bool _isSaving = false;

  Future<void> _salvarConfiguracoesDrive() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('settings').doc('googledrive').set({
        'rootFolderId': _folderIdCtrl.text.trim(),
        'frequency': _backupFrequencyCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'status': 'active',
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Configurações de Backup atualizadas!')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Erro: $e')));
    } finally {
      setState(() => _isSaving = false);
    }
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
        title: const Text('INFRAESTRUTURA DE DADOS'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _headerGoogleDrive(),
            const SizedBox(height: 30),
            _buildInputField('ID da Pasta Raiz (Google Drive)', _folderIdCtrl),
            const SizedBox(height: 16),
            _buildInputField('Frequência de Backup', _backupFrequencyCtrl),
            const SizedBox(height: 40),
            _botaoSalvarBackup(),
            const SizedBox(height: 24),
            _statusStorage(),
          ],
        ),
      ),
    ),
    );
  }

  Widget _headerGoogleDrive() => Row(
    children: [
      const Icon(Icons.cloud_sync, color: Colors.blueAccent, size: 40),
      const SizedBox(width: 15),
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('GOOGLE DRIVE BACKUP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          Text('Status: Conectado ao ID Raiz', style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
        ],
      ),
    ],
  );

  Widget _buildInputField(String label, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        FastTextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF1D1E33),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            suffixIcon: const Icon(Icons.folder_shared, color: Colors.blueAccent, size: 18),
          ),
        ),
      ],
    );
  }

  Widget _botaoSalvarBackup() => SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      onPressed: _isSaving ? null : _salvarConfiguracoesDrive,
      icon: const Icon(Icons.save, color: Colors.white),
      label: const Text('SALVAR CONFIGURAÇÕES', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blueAccent,
        padding: const EdgeInsets.symmetric(vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    ),
  );

  Widget _statusStorage() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: const Color(0xFF1D1E33), borderRadius: BorderRadius.circular(20)),
    child: const Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('ARMAZENAMENTO', style: TextStyle(color: Colors.white70, fontSize: 12)),
            Text('1.2 GB / 15 GB', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        SizedBox(height: 10),
        LinearProgressIndicator(value: 0.08, backgroundColor: Colors.white12, color: Colors.greenAccent),
      ],
    ),
  );
}
