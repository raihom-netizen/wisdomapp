import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart' hide showDatePicker;
import '../widgets/fast_text_field.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../constants/app_version.dart';
import '../models/budget_provider.dart';
import '../services/theme.dart';
import '../services/functions_service.dart';
import '../constants/currency_formats.dart';
import '../theme/app_colors.dart';
import '../utils/date_picker_a11y.dart';
import '../utils/firestore_user_doc_id.dart';

/// Formas de pagamento disponíveis no orçamento.
const List<String> kPaymentOptions = ['À vista PIX', 'Cartão', 'Parcelado', 'Entrada'];

class NewBudgetFlowScreen extends StatefulWidget {
  final String uid;

  const NewBudgetFlowScreen({super.key, required this.uid});

  @override
  State<NewBudgetFlowScreen> createState() => _NewBudgetFlowScreenState();
}

class _NewBudgetFlowScreenState extends State<NewBudgetFlowScreen> {
  int _step = 0;
  final _clientNameCtrl = TextEditingController();
  final _clientCpfCnpjCtrl = TextEditingController();
  final _clientContactCtrl = TextEditingController();
  final _clientAddressCtrl = TextEditingController();
  final _serviceDescCtrl = TextEditingController();
  final List<Map<String, dynamic>> _items = [];
  final Set<String> _paymentSelected = {'À vista PIX'};
  DateTime _dueDate = DateTime.now().add(const Duration(days: 7));
  int? _dueDays; // null = use _dueDate; else "válido por X dias"
  bool _iaLoading = false;
  bool _generating = false;
  BudgetProvider? _provider;
  StreamSubscription<fa.User?>? _authUidSub;

  CollectionReference<Map<String, dynamic>> get _quotes =>
      FirebaseFirestore.instance.collection('users').doc(firestoreUserDocIdForAppShell(widget.uid)).collection('quotes');
  CollectionReference<Map<String, dynamic>> get _templatesRef =>
      FirebaseFirestore.instance.collection('users').doc(firestoreUserDocIdForAppShell(widget.uid)).collection('budget_templates');
  DocumentReference<Map<String, dynamic>> get _providerRef =>
      FirebaseFirestore.instance.collection('users').doc(firestoreUserDocIdForAppShell(widget.uid)).collection('settings').doc('budget_provider');

  List<Map<String, dynamic>> _templates = [];
  bool _templatesLoaded = false;

  @override
  void initState() {
    super.initState();
    _authUidSub = fa.FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted) setState(() {});
    });
    _loadProvider();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    final snap = await _templatesRef.orderBy('name').get();
    if (mounted) {
      setState(() {
        _templates = snap.docs.map((d) => {'id': d.id, 'name': d.data()['name'] ?? '', 'items': List<Map<String, dynamic>>.from((d.data()['items'] as List? ?? []).map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{}))}).toList();
        _templatesLoaded = true;
      });
    }
  }

  Future<void> _loadProvider() async {
    final snap = await _providerRef.get();
    if (snap.exists && snap.data() != null) {
      setState(() => _provider = BudgetProvider.fromMap(snap.data()));
    }
  }

  @override
  void dispose() {
    _authUidSub?.cancel();
    _clientNameCtrl.dispose();
    _clientCpfCnpjCtrl.dispose();
    _clientContactCtrl.dispose();
    _clientAddressCtrl.dispose();
    _serviceDescCtrl.dispose();
    super.dispose();
  }

  double get _total => _items.fold<double>(0, (s, i) => s + ((i['value'] is num ? (i['value'] as num).toDouble() : 0.0) * ((i['qty'] is num ? (i['qty'] as num).toDouble() : 1.0))));

  Future<void> _transformWithIA() async {
    final text = _serviceDescCtrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Digite a descrição do serviço e valores.')));
      return;
    }
    setState(() => _iaLoading = true);
    try {
      final result = await FunctionsService().generateBudgetWithAI(text);
      if (!mounted) return;
      if (result != null && result['items'] is List) {
        _items.clear();
        for (final e in result['items'] as List) {
          final m = e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{};
          final name = (m['name'] ?? m['description'] ?? '').toString();
          final value = (m['value'] ?? m['valor'] ?? 0) is num ? (m['value'] ?? m['valor'] as num).toDouble() : 0.0;
          final qty = (m['qty'] is num) ? (m['qty'] as num).toDouble() : 1.0;
          if (name.isNotEmpty) _items.add({'name': name, 'value': value, 'qty': qty});
        }
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Itens gerados pela IA. Revise e avance.')));
      } else {
        _parseSimpleText(text);
        setState(() {});
      }
    } finally {
      if (mounted) setState(() => _iaLoading = false);
    }
  }

  void _parseSimpleText(String text) {
    _items.clear();
    final re = RegExp(r'([^,\n]+?)\s*[:\-]?\s*R?\$?\s*(\d+[,.]?\d*)', caseSensitive: false);
    for (final m in re.allMatches(text)) {
      final desc = m.group(1)?.trim() ?? '';
      final val = double.tryParse((m.group(2) ?? '0').replaceAll(',', '.')) ?? 0;
      if (desc.isNotEmpty && val > 0) _items.add({'name': desc, 'value': val, 'qty': 1.0});
    }
    if (_items.isEmpty) {
      final lines = text.split(RegExp(r'[\n,;]'));
      for (final line in lines) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          final last = parts.last.replaceAll(RegExp(r'[^\d,.]'), '').replaceAll(',', '.');
          final val = double.tryParse(last);
          if (val != null && val > 0) {
            final desc = parts.take(parts.length - 1).join(' ').trim();
            if (desc.isNotEmpty) _items.add({'name': desc, 'value': val, 'qty': 1.0});
          }
        }
      }
    }
  }

  Future<void> _generateAndSave() async {
    if (_clientNameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe o nome do cliente.')));
      return;
    }
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Adicione itens ao orçamento (use a IA ou digite descrição e valor).')));
      return;
    }
    setState(() => _generating = true);
    try {
      final due = _dueDays != null ? DateTime.now().add(Duration(days: _dueDays!)) : _dueDate;
      final quoteData = {
        'clientName': _clientNameCtrl.text.trim(),
        'clientCpfCnpj': _clientCpfCnpjCtrl.text.trim(),
        'clientContact': _clientContactCtrl.text.trim(),
        'clientAddress': _clientAddressCtrl.text.trim(),
        'items': _items,
        'total': _total,
        'payment': _paymentSelected.join(', '),
        'dueDate': Timestamp.fromDate(due),
        'dueDays': _dueDays,
        'createdAt': FieldValue.serverTimestamp(),
        'title': 'Orçamento ${_clientNameCtrl.text.trim()}',
      };
      final docRef = await _quotes.add(quoteData);

      final bytes = await _buildPdfBytes(
        clientName: quoteData['clientName'] as String,
        clientCpfCnpj: quoteData['clientCpfCnpj'] as String,
        clientContact: quoteData['clientContact'] as String,
        clientAddress: quoteData['clientAddress'] as String,
        items: _items,
        total: _total,
        payment: quoteData['payment'] as String,
        dueDate: due,
      );
      final uploadResult = await FunctionsService().uploadBudgetPdfToStorage(
        budgetPath: 'users/${widget.uid}/quotes/${docRef.id}',
        filename: 'orcamento_${docRef.id}.pdf',
        bytes: bytes,
      );
      final downloadUrl = (uploadResult['downloadUrl'] ?? uploadResult['url'] ?? '').toString();
      await docRef.update({
        'pdf': {
          'generated': true,
          'updatedAt': FieldValue.serverTimestamp(),
          if (downloadUrl.isNotEmpty) 'downloadUrl': downloadUrl,
        },
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Orçamento gerado e PDF criado!')));
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.success, size: 28),
                const SizedBox(width: 10),
                const Text('Orçamento gerado!'),
              ],
            ),
            content: const Text('Quer compartilhar o PDF ou ver na lista de orçamentos?'),
            actions: [
              if (downloadUrl.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Share.share(
                      'Orçamento WISDOMAPP\n$downloadUrl',
                      subject: 'Orçamento ${_clientNameCtrl.text.trim()}',
                    );
                  },
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('Compartilhar'),
                ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Ver lista'),
              ),
            ],
          ),
        );
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  /// Carrega bytes de imagem a partir da URL (logo do prestador).
  Future<Uint8List?> _loadImageBytes(String? url) async {
    if (url == null || url.trim().isEmpty) return null;
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) return null;
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) return res.bodyBytes;
    } catch (_) {}
    return null;
  }

  Future<Uint8List> _buildPdfBytes({
    required String clientName,
    required String clientCpfCnpj,
    required String clientContact,
    required String clientAddress,
    required List<Map<String, dynamic>> items,
    required double total,
    required String payment,
    required DateTime dueDate,
  }) async {
    final doc = pw.Document();
    final brandBlue = PdfColor.fromInt(0xFF2D5BFF);

    final logoBytes = await _loadImageBytes(_provider?.logoUrl);
    final providerName = _provider?.nomeFantasia.isNotEmpty == true
        ? _provider!.nomeFantasia
        : (_provider?.name.isNotEmpty == true ? _provider!.name : 'Prestador');

    final headerLeftChildren = <pw.Widget>[
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (logoBytes != null && logoBytes.isNotEmpty) ...[
            pw.Container(
              margin: const pw.EdgeInsets.only(right: 12),
              child: pw.Image(pw.MemoryImage(logoBytes), width: 56, height: 56, fit: pw.BoxFit.contain),
            ),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(providerName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                if (_provider?.cpfCnpj.isNotEmpty == true) pw.Text('CPF/CNPJ: ${_provider!.cpfCnpj}', style: const pw.TextStyle(fontSize: 9)),
                if (_provider?.contact.isNotEmpty == true) pw.Text('Contato: ${_provider!.contact}', style: const pw.TextStyle(fontSize: 9)),
                if (_provider?.address.isNotEmpty == true) pw.Text('Endereço: ${_provider!.address}', style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ),
        ],
      ),
    ];

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: brandBlue, width: 2))),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: headerLeftChildren)),
              pw.Text('ORÇAMENTO', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: brandBlue)),
            ],
          ),
        ),
        footer: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300))),
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text(
                'WISDOMAPP | v${AppVersion.current} - Seguranca e Gestao',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'wisdomapp-b9e98.web.app',
                style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
              ),
            ],
          ),
        ),
        build: (ctx) => [
          pw.SizedBox(height: 16),
          pw.Text('Cliente', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('Nome: $clientName'),
          if (clientCpfCnpj.isNotEmpty) pw.Text('CPF/CNPJ: $clientCpfCnpj'),
          if (clientContact.isNotEmpty) pw.Text('Contato: $clientContact'),
          if (clientAddress.isNotEmpty) pw.Text('Endereço: $clientAddress'),
          pw.SizedBox(height: 8),
          pw.Text('Data: ${dueDate.day.toString().padLeft(2, '0')}/${dueDate.month.toString().padLeft(2, '0')}/${dueDate.year}', style: const pw.TextStyle(fontSize: 10)),
          pw.Text('Válido até: ${dueDate.day.toString().padLeft(2, '0')}/${dueDate.month.toString().padLeft(2, '0')}/${dueDate.year}', style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 16),
          pw.Text('Serviços', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: brandBlue, fontSize: 10),
            headers: ['Descrição', 'Qtd', 'Valor unit.', 'Total'],
            data: items.map((i) {
              final qty = (i['qty'] is num ? (i['qty'] as num).toDouble() : 1.0);
              final unit = (i['value'] is num ? (i['value'] as num).toDouble() : 0.0);
              final lineTotal = qty * unit;
              return [(i['name'] ?? '').toString(), qty.toStringAsFixed(0), CurrencyFormats.formatBRL(unit), CurrencyFormats.formatBRL(lineTotal)];
            }).toList(),
            cellStyle: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFE8F0FF), borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Forma de pagamento: $payment', style: const pw.TextStyle(fontSize: 10)),
                pw.Text('TOTAL: ${CurrencyFormats.formatBRL(total)}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: brandBlue)),
              ],
            ),
          ),
        ],
      ),
    );

    return Uint8List.fromList(await doc.save());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Novo orçamento'),
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
      ),
      body: SafeArea(
        child: Column(
        children: [
          LinearProgressIndicator(value: (_step + 1) / 4, backgroundColor: Colors.grey.shade200, valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary)),
          Expanded(
            child: _step == 0 ? _buildStepClient() : _step == 1 ? _buildStepService() : _step == 2 ? _buildStepPayment() : _buildStepGenerate(),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (_step > 0)
                  OutlinedButton(
                    onPressed: () => setState(() => _step--),
                    child: const Text('Voltar'),
                  ),
                if (_step > 0) const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      if (_step < 3) {
                        if (_step == 0 && _clientNameCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe o nome do cliente.')));
                          return;
                        }
                        setState(() => _step++);
                      } else {
                        await _generateAndSave();
                      }
                    },
                    child: Text(_step == 3 ? (_generating ? 'Gerando PDF...' : 'Gerar orçamento') : 'Continuar'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildStepClient() {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        Text('Dados do cliente', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('Preencha para identificar o cliente no orçamento.', style: TextStyle(color: AppColors.textMuted)),
        const SizedBox(height: 20),
        FastTextField(
          controller: _clientNameCtrl,
          decoration: const InputDecoration(
            labelText: 'Nome (pessoa ou empresa) *',
            hintText: 'Ex: Maria Silva ou Empresa XYZ',
          ),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 12),
        FastTextField(
          controller: _clientCpfCnpjCtrl,
          decoration: const InputDecoration(
            labelText: 'CPF ou CNPJ (opcional)',
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        FastTextField(
          controller: _clientContactCtrl,
          decoration: const InputDecoration(labelText: 'Contato', hintText: 'Telefone ou e-mail'),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        FastTextField(
          controller: _clientAddressCtrl,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Endereço', hintText: 'Rua, número, bairro, cidade'),
        ),
      ],
    );
  }

  Future<void> _saveAsTemplate() async {
    if (_items.isEmpty) return;
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salvar como modelo'),
        content: FastTextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Nome do modelo',
            hintText: 'Ex: Instalação elétrica',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe o nome do modelo.')));
      return;
    }
    await _templatesRef.add({'name': name, 'items': _items, 'createdAt': FieldValue.serverTimestamp()});
    await _loadTemplates();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Modelo salvo. Use em "Usar modelo".')));
  }

  Widget _buildStepService() {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        Text('Descrição do serviço', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('Digite tudo que vai fazer e o valor. Use a IA ou um modelo.', style: TextStyle(color: AppColors.textMuted)),
        if (_templatesLoaded && _templates.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Usar modelo', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          DropdownButtonFormField<Map<String, dynamic>>(
            value: null,
            decoration: const InputDecoration(
              labelText: 'Escolha um modelo para preencher os itens',
              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
            ),
            items: [
              const DropdownMenuItem<Map<String, dynamic>>(value: null, child: Text('Nenhum')),
              ..._templates.map((t) => DropdownMenuItem<Map<String, dynamic>>(
                    value: t,
                    child: Text(t['name']?.toString() ?? ''),
                  )),
            ],
            onChanged: (t) {
              if (t == null) return;
              final items = t['items'] as List? ?? [];
              setState(() {
                _items.clear();
                for (final e in items) {
                  final m = e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{};
                  _items.add({
                    'name': m['name'] ?? '',
                    'value': (m['value'] is num ? (m['value'] as num).toDouble() : 0.0),
                    'qty': (m['qty'] is num ? (m['qty'] as num).toDouble() : 1.0),
                  });
                }
              });
            },
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 16),
        FastTextField(
          controller: _serviceDescCtrl,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: 'Ex: Cliente Maria, instalação de 4 tomadas R\$ 30 cada, 2 interruptores R\$ 25 cada, garantia 90 dias',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            filled: true,
          ),
        ),
        const SizedBox(height: 8),
        Text('Este recurso utiliza IA e está sujeito a erros. Revise os dados.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _iaLoading ? null : _transformWithIA,
          icon: _iaLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.auto_awesome_rounded),
          label: Text(_iaLoading ? 'Gerando itens...' : 'Transformar em itens (IA)'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        ),
        if (_items.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Itens do orçamento', style: TextStyle(fontWeight: FontWeight.w700)),
              TextButton.icon(
                onPressed: _saveAsTemplate,
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text('Salvar como modelo'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._items.asMap().entries.map((e) {
            final i = e.value;
            final qty = (i['qty'] is num ? (i['qty'] as num).toDouble() : 1.0);
            final unit = (i['value'] is num ? (i['value'] as num).toDouble() : 0.0);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(i['name']?.toString() ?? ''),
                subtitle: Text('${qty.toInt()} x ${CurrencyFormats.formatBRL(unit)} = ${CurrencyFormats.formatBRL(qty * unit)}'),
              ),
            );
          }),
          const SizedBox(height: 8),
          Text('Total: ${CurrencyFormats.formatBRL(_total)}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
        ],
      ],
    );
  }

  Widget _buildStepPayment() {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        Text('Pagamento e vencimento', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        const Text('Forma de pagamento', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kPaymentOptions.map((opt) {
            final sel = _paymentSelected.contains(opt);
            return FilterChip(
              label: Text(opt),
              selected: sel,
              onSelected: (v) {
                setState(() {
                  if (v) _paymentSelected.add(opt); else _paymentSelected.remove(opt);
                });
              },
              selectedColor: AppColors.primary.withOpacity(0.3),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        const Text('Vencimento do orçamento', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ListTile(
          title: const Text('Escolher data'),
          subtitle: Text('${_dueDate.day.toString().padLeft(2, '0')}/${_dueDate.month.toString().padLeft(2, '0')}/${_dueDate.year}'),
          trailing: const Icon(Icons.calendar_today_rounded),
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: _dueDate, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
            if (d != null) setState(() { _dueDate = d; _dueDays = null; });
          },
        ),
        ListTile(
          title: const Text('Válido por X dias'),
          subtitle: Text(_dueDays != null ? '$_dueDays dias' : 'Toque para definir'),
          trailing: const Icon(Icons.today_rounded),
          onTap: () async {
            final c = TextEditingController(text: _dueDays?.toString() ?? '7');
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Quantidade de dias'),
                content: FastTextField(
                  controller: c,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Dias de validade'),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
                ],
              ),
            );
            if (ok == true) {
              final days = int.tryParse(c.text);
              if (days != null && days > 0) setState(() { _dueDays = days; });
            }
          },
        ),
        const SizedBox(height: 16),
        Card(
          color: AppColors.primary.withOpacity(0.08),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total do orçamento', style: TextStyle(fontWeight: FontWeight.w700)),
                Text(CurrencyFormats.formatBRL(_total), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepGenerate() {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        Icon(Icons.check_circle_outline_rounded, size: 64, color: AppColors.success),
        const SizedBox(height: 16),
        Text('Revisar e gerar', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('Cliente: ${_clientNameCtrl.text.trim()}', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text('${_items.length} itens • Total ${CurrencyFormats.formatBRL(_total)}'),
        Text('Pagamento: ${_paymentSelected.join(', ')}'),
        Text('Válido até: ${_dueDays != null ? 'em $_dueDays dias' : '${_dueDate.day.toString().padLeft(2, '0')}/${_dueDate.month.toString().padLeft(2, '0')}/${_dueDate.year}'}'),
        const SizedBox(height: 24),
        Text('O sistema usará a IA e os dados do prestador para criar um PDF com cabeçalho, tabela de itens e rodapé do WISDOMAPP.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ],
    );
  }
}

