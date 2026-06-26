import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../models/budget_provider.dart';
import '../services/theme.dart';
import '../theme/app_colors.dart';

class BudgetProviderScreen extends StatefulWidget {
  final String uid;

  const BudgetProviderScreen({super.key, required this.uid});

  DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('settings').doc('budget_provider');

  @override
  State<BudgetProviderScreen> createState() => _BudgetProviderScreenState();
}

class _BudgetProviderScreenState extends State<BudgetProviderScreen> {
  final _nameCtrl = TextEditingController();
  final _nomeFantasiaCtrl = TextEditingController();
  final _cpfCnpjCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _logoUrlCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _uploadingLogo = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snap = await widget._ref.get();
    if (snap.exists && snap.data() != null) {
      final p = BudgetProvider.fromMap(snap.data());
      _nameCtrl.text = p.name;
      _nomeFantasiaCtrl.text = p.nomeFantasia;
      _cpfCnpjCtrl.text = p.cpfCnpj;
      _contactCtrl.text = p.contact;
      _addressCtrl.text = p.address;
      _logoUrlCtrl.text = p.logoUrl;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nomeFantasiaCtrl.dispose();
    _cpfCnpjCtrl.dispose();
    _contactCtrl.dispose();
    _addressCtrl.dispose();
    _logoUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadLogo() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Use a URL da logo no campo abaixo (upload em breve na web).')));
      return;
    }
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (xfile == null || !mounted) return;
    setState(() => _uploadingLogo = true);
    try {
      final bytes = await xfile.readAsBytes();
      final ref = FirebaseStorage.instance.ref().child('users/${widget.uid}/budget_provider_logo.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      _logoUrlCtrl.text = url;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logo enviada. Toque em Salvar.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao enviar: $e')));
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final p = BudgetProvider(
        name: _nameCtrl.text.trim(),
        nomeFantasia: _nomeFantasiaCtrl.text.trim(),
        cpfCnpj: _cpfCnpjCtrl.text.trim(),
        contact: _contactCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        logoUrl: _logoUrlCtrl.text.trim(),
      );
      await widget._ref.set(p.toMap(), SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dados do prestador salvos.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dados do prestador'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context)),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.business_rounded, color: AppColors.primary),
                      const SizedBox(width: 10),
                      const Text('Estes dados aparecem no cabeçalho do orçamento PDF', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FastTextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nome (pessoa ou empresa) *',
                      hintText: 'Seu nome ou razão social',
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  FastTextField(
                    controller: _nomeFantasiaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nome fantasia (opcional)',
                      hintText: 'Ex: João Serviços Elétricos',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FastTextField(
                    controller: _cpfCnpjCtrl,
                    decoration: const InputDecoration(
                      labelText: 'CPF ou CNPJ (opcional)',
                      hintText: '00.000.000/0000-00',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  FastTextField(
                    controller: _contactCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Contato',
                      hintText: 'Telefone ou e-mail',
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  FastTextField(
                    controller: _addressCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Endereço',
                      hintText: 'Rua, número, bairro, cidade',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.image_rounded, color: AppColors.primary, size: 22),
                            const SizedBox(width: 8),
                            const Text('Incluir minha logo no orçamento', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Se quiser, adicione sua logo para aparecer no cabeçalho dos PDFs. Deixe em branco para não usar logo.',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _uploadingLogo ? null : _pickAndUploadLogo,
                          icon: _uploadingLogo ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_rounded),
                          label: Text(_uploadingLogo ? 'Enviando...' : 'Carregar logo do celular'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 8),
                        FastTextField(
                          controller: _logoUrlCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Ou cole a URL da logo (opcional)',
                            hintText: 'Link de uma imagem da sua marca',
                            prefixIcon: Icon(Icons.link_rounded),
                          ),
                          keyboardType: TextInputType.url,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_rounded),
            label: const Text('Salvar'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: AppColors.deepBlueDark,
            ),
          ),
        ],
      ),
      ),
    );
  }
}
