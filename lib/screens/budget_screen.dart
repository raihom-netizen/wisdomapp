import 'dart:async';

import 'package:flutter/material.dart' hide showDatePicker;
import '../widgets/fast_text_field.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import '../models/user_profile.dart';
import '../services/functions_service.dart';
import '../theme/app_colors.dart';
import '../constants/currency_formats.dart';
import '../utils/date_picker_a11y.dart';
import '../constants/app_business_rules.dart';
import '../utils/firestore_user_doc_id.dart';
import '../widgets/brl_amount_text_field.dart';

class BudgetScreen extends StatefulWidget {
  final String uid;
  final UserProfile profile;
  const BudgetScreen({super.key, required this.uid, required this.profile});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  StreamSubscription<fa.User?>? _authUidSub;

  @override
  void initState() {
    super.initState();
    _authUidSub = fa.FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _authUidSub?.cancel();
    super.dispose();
  }

  String _monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
  String _monthLabel(DateTime d) => '${d.month.toString().padLeft(2, '0')}/${d.year}';

  DateTime _monthStart(DateTime d) => DateTime(d.year, d.month, 1);
  DateTime _monthEnd(DateTime d) => DateTime(d.year, d.month + 1, 1);

  void _prevMonth() => setState(() => _month = DateTime(_month.year, _month.month - 1, 1));
  void _nextMonth() => setState(() => _month = DateTime(_month.year, _month.month + 1, 1));

  @override
  Widget build(BuildContext context) {
    if (!widget.profile.temAcessoPremium && !widget.profile.isAdmin) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Assine o plano para acessar metas, limites, projeções e simulador.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  colors: [AppColors.deepBlueDark, AppColors.deepBlue, AppColors.accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(color: AppColors.deepBlueDark.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 10)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Image.asset('assets/images/icon.png', height: 32, width: 32, errorBuilder: (_, __, ___) => const Icon(Icons.apps_rounded, color: Colors.white, size: 32)),
                      const SizedBox(width: 10),
                      const Text(
                        'Orçamento Premium',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _prevMonth,
                        icon: const Icon(Icons.chevron_left, color: Colors.white),
                      ),
                      Text(
                        _monthLabel(_month),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                      IconButton(
                        onPressed: _nextMonth,
                        icon: const Icon(Icons.chevron_right, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Planejamento financeiro, metas, projeções e PDFs com sua marca.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.deepBlueDark,
                borderRadius: BorderRadius.circular(16),
              ),
              child: TabBar(
                isScrollable: true,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: AppColors.primary,
                indicatorWeight: 3,
                tabs: const [
                  Tab(text: 'Limites'),
                  Tab(text: 'Metas'),
                  Tab(text: 'Projeção'),
                  Tab(text: 'Fixas/Variáveis'),
                  Tab(text: 'Pagamentos'),
                  Tab(text: 'Simulador'),
                  Tab(text: 'Orçamentos PDF'),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _BudgetLimitsTab(uid: widget.uid, month: _month, monthKey: _monthKey(_month), monthStart: _monthStart(_month), monthEnd: _monthEnd(_month)),
                _GoalsTab(uid: widget.uid),
                _ProjectionTab(uid: widget.uid, month: _month, monthStart: _monthStart(_month), monthEnd: _monthEnd(_month)),
                _FixedVariableTab(uid: widget.uid, monthStart: _monthStart(_month), monthEnd: _monthEnd(_month)),
                _PaymentsTab(uid: widget.uid, monthStart: _monthStart(_month), monthEnd: _monthEnd(_month)),
                _SimulatorTab(uid: widget.uid, monthStart: _monthStart(_month), monthEnd: _monthEnd(_month)),
                _QuotesTab(uid: widget.uid),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuotesTab extends StatelessWidget {
  final String uid;
  const _QuotesTab({required this.uid});

  CollectionReference<Map<String, dynamic>> get _quotes =>
      FirebaseFirestore.instance.collection('users').doc(firestoreUserDocIdForAppShell(uid)).collection('quotes');

  String _sanitize(String input) =>
      input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_').replaceAll(RegExp(r'[^a-z0-9_\-]'), '');

  Future<void> _createQuote(BuildContext context) async {
    final titleCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final itemNameCtrl = TextEditingController();
    final itemValueCtrl = TextEditingController();
    final items = <Map<String, dynamic>>[];

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Novo orçamento'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              FastTextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Título')),
              const SizedBox(height: 8),
              FastTextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Observações')),
              const SizedBox(height: 12),
              const Align(alignment: Alignment.centerLeft, child: Text('Itens')),
              const SizedBox(height: 6),
              FastTextField(controller: itemNameCtrl, decoration: const InputDecoration(labelText: 'Item')),
              const SizedBox(height: 6),
              BrlAmountTextField(
                controller: itemValueCtrl,
                decoration: const InputDecoration(labelText: 'Valor'),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar item'),
                      onPressed: () {
                        final name = itemNameCtrl.text.trim();
                        final value = CurrencyFormats.parseBRLInput(itemValueCtrl.text) ?? 0;
                        if (name.isEmpty || value <= 0) return;
                        items.add({'name': name, 'value': value});
                        itemNameCtrl.clear();
                        itemValueCtrl.clear();
                        setState(() {});
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (items.isNotEmpty)
                Column(
                  children: items
                      .map((i) => ListTile(
                            title: Text(i['name'].toString()),
                            trailing: Text(CurrencyFormats.formatBRL(i['value'] as double)),
                          ))
                      .toList(),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final title = titleCtrl.text.trim();
    if (title.isEmpty || items.isEmpty) return;
    final total = items.fold<double>(0, (total, i) => total + (i['value'] as double));

    await _quotes.add({
      'title': title,
      'notes': notesCtrl.text.trim(),
      'items': items,
      'total': total,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<int>> _buildPdf(Map<String, dynamic> data) async {
    final doc = pw.Document();
    final title = (data['title'] ?? 'Orçamento').toString();
    final notes = (data['notes'] ?? '').toString();
    final items = (data['items'] as List? ?? []).cast<Map>();
    final total = (data['total'] ?? 0).toDouble();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Orçamento', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Text(title, style: pw.TextStyle(fontSize: 16)),
              pw.SizedBox(height: 12),
              pw.TableHelper.fromTextArray(
                headers: ['Item', 'Valor (R\$)'],
                data: items.map((i) => [i['name'] ?? '', CurrencyFormats.formatBRLNumberOnly((i['value'] ?? 0) as num)]).toList(),
              ),
              pw.SizedBox(height: 12),
              pw.Text('Total: ${CurrencyFormats.formatBRL(total)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              if (notes.isNotEmpty) ...[
                pw.SizedBox(height: 12),
                pw.Text('Observações:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text(notes),
              ],
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  Future<void> _uploadPdf(BuildContext context, DocumentSnapshot<Map<String, dynamic>> docSnap) async {
    final data = docSnap.data() ?? {};
    final title = (data['title'] ?? 'orcamento').toString();
    final date = DateTime.now();
    final filename = 'orcamento_${_sanitize(title)}_${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}.pdf';

    final bytes = await _buildPdf(data);
    final fn = FunctionsService();
    final budgetPath = 'users/$uid/quotes/${docSnap.id}';
    await fn.uploadBudgetPdfToStorage(budgetPath: budgetPath, filename: filename, bytes: bytes);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF gerado e enviado ao Firebase.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _quotes.orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Criar orçamento PDF'),
              onPressed: () => _createQuote(context),
            ),
            const SizedBox(height: 12),
            if (docs.isEmpty)
              const Center(child: Text('Nenhum orçamento criado.')),
            ...docs.map((doc) {
              final data = doc.data();
              final total = (data['total'] ?? 0).toDouble();
              final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
              final pdf = Map<String, dynamic>.from(data['pdf'] ?? {});
              final link = (pdf['downloadUrl'] ?? pdf['webViewLink'] ?? '').toString();

              return Card(
                child: ListTile(
                  title: Text(data['title'] ?? 'Orçamento'),
                  subtitle: Text('Total: ${CurrencyFormats.formatBRL(total)}${createdAt == null ? '' : ' • ${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year}'}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.picture_as_pdf),
                        tooltip: 'Gerar PDF',
                        onPressed: () => _uploadPdf(context, doc),
                      ),
                      if (link.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.link),
                          tooltip: 'Ver link',
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Link do PDF'),
                                content: Text(link),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _BudgetLimitsTab extends StatelessWidget {
  final String uid;
  final DateTime month;
  final String monthKey;
  final DateTime monthStart;
  final DateTime monthEnd;
  const _BudgetLimitsTab({
    required this.uid,
    required this.month,
    required this.monthKey,
    required this.monthStart,
    required this.monthEnd,
  });

  CollectionReference<Map<String, dynamic>> get _budgets =>
      FirebaseFirestore.instance.collection('users').doc(firestoreUserDocIdForAppShell(uid)).collection('budgets');
  CollectionReference<Map<String, dynamic>> get _tx =>
      FirebaseFirestore.instance.collection('users').doc(firestoreUserDocIdForAppShell(uid)).collection('transactions');

  Future<void> _addBudget(BuildContext context) async {
    final catCtrl = TextEditingController();
    final limitCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Novo limite por categoria'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          FastTextField(controller: catCtrl, decoration: const InputDecoration(labelText: 'Categoria')),
          const SizedBox(height: 10),
          BrlAmountTextField(
            controller: limitCtrl,
            decoration: const InputDecoration(labelText: 'Teto mensal (ex: 500,00)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salvar')),
        ],
      ),
    );

    if (ok != true) return;
    final limit = CurrencyFormats.parseBRLInput(limitCtrl.text) ?? 0;
    final category = catCtrl.text.trim();
    if (category.isEmpty || limit <= 0) return;

    await _budgets.add({
      'category': category,
      'monthlyLimit': limit,
      'month': monthKey,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _copyPreviousMonth(BuildContext context) async {
    final prev = DateTime(month.year, month.month - 1, 1);
    final prevKey = '${prev.year}-${prev.month.toString().padLeft(2, '0')}';

    final snap = await _budgets.where('month', isEqualTo: prevKey).get();
    if (snap.docs.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      final data = doc.data();
      batch.set(_budgets.doc(), {
        'category': data['category'] ?? '',
        'monthlyLimit': data['monthlyLimit'] ?? 0,
        'month': monthKey,
        'createdAt': FieldValue.serverTimestamp(),
        'copiedFrom': prevKey,
      });
    }
    await batch.commit();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Limites copiados do mês anterior.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final txStream = _tx
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
        .where('date', isLessThan: Timestamp.fromDate(monthEnd))
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: txStream,
      builder: (context, txSnap) {
        if (!txSnap.hasData) return const Center(child: CircularProgressIndicator());
        final spentByCategory = <String, double>{};
        for (final doc in txSnap.data!.docs) {
          final d = doc.data();
          if (d['type'] != 'expense') continue;
          final category = (d['category'] ?? 'Sem categoria').toString();
          final amount = (d['amount'] ?? 0).toDouble();
          spentByCategory[category] = (spentByCategory[category] ?? 0) + amount;
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _budgets.where('month', isEqualTo: monthKey).snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snap.data!.docs;

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Row(
                  children: [
                    Expanded(child: ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar limite'),
                      onPressed: () => _addBudget(context),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: OutlinedButton.icon(
                      icon: const Icon(Icons.copy),
                      label: const Text('Copiar mês anterior'),
                      onPressed: () => _copyPreviousMonth(context),
                    )),
                  ],
                ),
                const SizedBox(height: 12),
                if (docs.isEmpty)
                  const Center(child: Text('Nenhum limite definido para este mês.')),
                ...docs.map((doc) {
                  final d = doc.data();
                  final category = (d['category'] ?? '').toString();
                  final limit = (d['monthlyLimit'] ?? 0).toDouble();
                  final spent = spentByCategory[category] ?? 0;
                  final ratio = (limit > 0 ? (spent / limit) : 0).clamp(0.0, 2.0).toDouble();
                  final status = ratio >= 1
                      ? 'Limite atingido'
                      : ratio >= 0.7
                          ? 'Atenção: 70%'
                          : 'Dentro do limite';

                  return Card(
                    child: ListTile(
                      title: Text(category.isEmpty ? 'Sem categoria' : category),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          LinearProgressIndicator(value: ratio > 1 ? 1 : ratio),
                          const SizedBox(height: 6),
                          Text('Gasto: ${CurrencyFormats.formatBRL(spent)} / Limite: ${CurrencyFormats.formatBRL(limit)}'),
                          Text(status, style: TextStyle(color: ratio >= 1 ? Colors.red : (ratio >= 0.7 ? Colors.orange : Colors.green))),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }
}

class _GoalsTab extends StatelessWidget {
  final String uid;
  const _GoalsTab({required this.uid});

  CollectionReference<Map<String, dynamic>> get _goals =>
      FirebaseFirestore.instance.collection('users').doc(firestoreUserDocIdForAppShell(uid)).collection('goals');
  CollectionReference<Map<String, dynamic>> get _tx =>
      FirebaseFirestore.instance.collection('users').doc(firestoreUserDocIdForAppShell(uid)).collection('transactions');

  Future<void> _addGoal(BuildContext context) async {
    final titleCtrl = TextEditingController();
    final targetCtrl = TextEditingController();
    DateTime? due;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Nova meta financeira'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            FastTextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Título da meta')),
            const SizedBox(height: 10),
            BrlAmountTextField(
              controller: targetCtrl,
              decoration: const InputDecoration(labelText: 'Valor alvo'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: Text(due == null ? 'Sem prazo' : 'Prazo: ${due!.day.toString().padLeft(2, '0')}/${due!.month.toString().padLeft(2, '0')}/${due!.year}')),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => due = picked);
                  },
                  child: const Text('Definir prazo'),
                ),
              ],
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final target = CurrencyFormats.parseBRLInput(targetCtrl.text) ?? 0;
    final title = titleCtrl.text.trim();
    if (title.isEmpty || target <= 0) return;

    await _goals.add({
      'title': title,
      'targetAmount': target,
      'dueDate': due != null ? Timestamp.fromDate(due!) : null,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'active',
    });
  }

  Future<void> _addContribution(BuildContext context, String goalId, String goalTitle) async {
    final amountCtrl = TextEditingController();
    DateTime date = DateTime.now();
    bool asIncome = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Registrar contribuição'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            BrlAmountTextField(
              controller: amountCtrl,
              decoration: const InputDecoration(labelText: 'Valor'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: Text('Data: ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}')),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => date = picked);
                  },
                  child: const Text('Alterar'),
                ),
              ],
            ),
            CheckboxListTile(
              value: asIncome,
              onChanged: (v) => setState(() => asIncome = v ?? true),
              title: const Text('Registrar também como receita real'),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final amount = CurrencyFormats.parseBRLInput(amountCtrl.text) ?? 0;
    if (amount <= 0) return;

    final goalRef = _goals.doc(goalId);
    await goalRef.collection('contributions').add({
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (asIncome) {
      await _tx.add({
        'type': 'income',
        'amount': amount,
        'category': 'Meta',
        'description': 'Contribuição para $goalTitle',
        'date': Timestamp.fromDate(date),
        'goalId': goalId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _goals.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.flag),
              label: const Text('Criar meta'),
              onPressed: () => _addGoal(context),
            ),
            const SizedBox(height: 12),
            if (docs.isEmpty)
              const Center(child: Text('Nenhuma meta cadastrada.')),
            ...docs.map((doc) {
              final data = doc.data();
              final title = (data['title'] ?? '').toString();
              final target = (data['targetAmount'] ?? 0).toDouble();
              final dueTs = data['dueDate'] as Timestamp?;

              return Card(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: doc.reference.collection('contributions').snapshots(),
                  builder: (context, cSnap) {
                    final contribDocs = cSnap.data?.docs ?? [];
                    final contribSum = contribDocs.fold<double>(0, (total, d) => total + ((d.data()['amount'] ?? 0).toDouble()));

                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _tx.where('goalId', isEqualTo: doc.id).snapshots(),
                      builder: (context, txSnap) {
                        final txDocs = txSnap.data?.docs ?? [];
                        final txSum = txDocs.fold<double>(0, (total, d) => total + ((d.data()['amount'] ?? 0).toDouble()));
                        final progress = contribSum + txSum;
                        final ratio = (target > 0 ? (progress / target) : 0).clamp(0.0, 1.0).toDouble();

                        String recommended = '';
                        if (dueTs != null) {
                          final due = dueTs.toDate();
                          final months = ((due.year - DateTime.now().year) * 12 + (due.month - DateTime.now().month)).clamp(1, 120);
                          final remaining = (target - progress).clamp(0, target);
                          final perMonth = remaining / months;
                          recommended = 'Recomendado: ${CurrencyFormats.formatBRL(perMonth)}/mês';
                        }

                        return ListTile(
                          title: Text(title),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 6),
                              LinearProgressIndicator(value: ratio),
                              const SizedBox(height: 6),
                              Text('Progresso: ${CurrencyFormats.formatBRL(progress)} / ${CurrencyFormats.formatBRL(target)}'),
                              if (dueTs != null)
                                Text('Prazo: ${dueTs.toDate().day.toString().padLeft(2, '0')}/${dueTs.toDate().month.toString().padLeft(2, '0')}/${dueTs.toDate().year}'),
                              if (recommended.isNotEmpty) Text(recommended),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            tooltip: 'Adicionar contribuição',
                            onPressed: () => _addContribution(context, doc.id, title),
                          ),
                        );
                      },
                    );
                  },
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _ProjectionTab extends StatelessWidget {
  final String uid;
  final DateTime month;
  final DateTime monthStart;
  final DateTime monthEnd;
  const _ProjectionTab({required this.uid, required this.month, required this.monthStart, required this.monthEnd});

  CollectionReference<Map<String, dynamic>> get _tx =>
      FirebaseFirestore.instance.collection('users').doc(firestoreUserDocIdForAppShell(uid)).collection('transactions');
  CollectionReference<Map<String, dynamic>> get _payments =>
      FirebaseFirestore.instance.collection('users').doc(firestoreUserDocIdForAppShell(uid)).collection('payments');

  @override
  Widget build(BuildContext context) {
    final txStream = _tx
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
        .where('date', isLessThan: Timestamp.fromDate(monthEnd))
        .snapshots();

    final prevMonth = DateTime(month.year, month.month - 1, 1);
    final prevStart = DateTime(prevMonth.year, prevMonth.month, 1);
    final prevEnd = DateTime(prevMonth.year, prevMonth.month + 1, 1);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: txStream,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        double income = 0;
        double expense = 0;
        final dailyExpense = <String, double>{};

        for (final doc in snap.data!.docs) {
          final d = doc.data();
          final amount = (d['amount'] ?? 0).toDouble();
          final date = (d['date'] as Timestamp?)?.toDate() ?? DateTime.now();
          final dayKey = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

          if (d['type'] == 'income') {
            income += amount;
          } else if (d['type'] == 'expense') {
            expense += amount;
            dailyExpense[dayKey] = (dailyExpense[dayKey] ?? 0) + amount;
          }
        }

        final criticalDays = dailyExpense.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _payments
              .where('dueDate', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
              .where('dueDate', isLessThan: Timestamp.fromDate(monthEnd))
              .snapshots(),
          builder: (context, paySnap) {
            final payments = paySnap.data?.docs ?? [];
            final planned = payments.fold<double>(0, (total, d) {
              final data = d.data();
              final paid = (data['paid'] ?? false) as bool;
              if (paid) return total;
              return total + ((data['amount'] ?? 0).toDouble());
            });

            final projected = income - expense - planned;

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _tx
                  .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(prevStart))
                  .where('date', isLessThan: Timestamp.fromDate(prevEnd))
                  .snapshots(),
              builder: (context, prevSnap) {
                double prevIncome = 0;
                double prevExpense = 0;
                for (final doc in prevSnap.data?.docs ?? []) {
                  final d = doc.data();
                  final amount = (d['amount'] ?? 0).toDouble();
                  if (d['type'] == 'income') prevIncome += amount;
                  if (d['type'] == 'expense') prevExpense += amount;
                }

                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.insights),
                        title: RichText(
                          text: TextSpan(
                            style: DefaultTextStyle.of(context).style.copyWith(color: Colors.black87),
                            children: [
                              const TextSpan(text: 'Saldo previsto: '),
                              TextSpan(
                                text: CurrencyFormats.formatBRL(projected),
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: projected >= 0 ? AppColors.saldoPositive : AppColors.saldoNegative,
                                ),
                              ),
                            ],
                          ),
                        ),
                        subtitle: Text('Receitas: ${CurrencyFormats.formatBRL(income)} | Despesas: ${CurrencyFormats.formatBRL(expense)} | Pagamentos: ${CurrencyFormats.formatBRL(planned)}'),
                      ),
                    ),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.compare_arrows),
                        title: const Text('Comparativo com mês anterior'),
                        subtitle: Text('Receitas: ${CurrencyFormats.formatBRL(prevIncome)} | Despesas: ${CurrencyFormats.formatBRL(prevExpense)}'),
                      ),
                    ),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.warning_amber),
                        title: const Text('Dias críticos'),
                        subtitle: criticalDays.isEmpty
                            ? const Text('Nenhum dia crítico identificado.')
                            : Text(criticalDays.take(3).map((e) => '${e.key}: ${CurrencyFormats.formatBRL(e.value)}').join(' • ')),
                      ),
                    ),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.auto_awesome, color: Color(0xFF2D5BFF)),
                        title: const Text('Sugestão IA'),
                        subtitle: Text(
                          projected < 0
                              ? 'Seu saldo previsto está negativo. Reduza despesas variáveis e renegocie pagamentos para evitar déficit.'
                              : projected < 500
                                  ? 'Saldo previsto baixo. Considere antecipar receitas e revisar gastos recorrentes.'
                                  : 'Saldo saudável. Você pode aumentar reservas ou investir parte do excedente.',
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _FixedVariableTab extends StatelessWidget {
  final String uid;
  final DateTime monthStart;
  final DateTime monthEnd;
  const _FixedVariableTab({required this.uid, required this.monthStart, required this.monthEnd});

  CollectionReference<Map<String, dynamic>> get _tx =>
      FirebaseFirestore.instance.collection('users').doc(firestoreUserDocIdForAppShell(uid)).collection('transactions');
  CollectionReference<Map<String, dynamic>> get _types =>
      FirebaseFirestore.instance.collection('users').doc(firestoreUserDocIdForAppShell(uid)).collection('category_types');

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _tx
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .where('date', isLessThan: Timestamp.fromDate(monthEnd))
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final categories = <String>{};
        final expenseByCategory = <String, double>{};

        for (final doc in snap.data!.docs) {
          final d = doc.data();
          if (d['type'] != 'expense') continue;
          final category = (d['category'] ?? 'Sem categoria').toString();
          final amount = (d['amount'] ?? 0).toDouble();
          categories.add(category);
          expenseByCategory[category] = (expenseByCategory[category] ?? 0) + amount;
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _types.snapshots(),
          builder: (context, typeSnap) {
            final typeDocs = typeSnap.data?.docs ?? [];
            final typeMap = <String, String>{
              for (final doc in typeDocs) (doc.data()['category'] ?? '').toString(): (doc.data()['type'] ?? 'variable').toString(),
            };

            double fixedTotal = 0;
            double variableTotal = 0;
            for (final entry in expenseByCategory.entries) {
              final t = typeMap[entry.key] ?? 'variable';
              if (t == 'fixed') {
                fixedTotal += entry.value;
              } else {
                variableTotal += entry.value;
              }
            }

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.pie_chart),
                    title: const Text('Proporção fixa x variável'),
                    subtitle: Text('Fixas: ${CurrencyFormats.formatBRL(fixedTotal)} • Variáveis: ${CurrencyFormats.formatBRL(variableTotal)}'),
                  ),
                ),
                if (variableTotal > fixedTotal)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.tips_and_updates),
                      title: Text('Sugestão'),
                      subtitle: Text('Variáveis altas este mês. Considere reduzir gastos não essenciais.'),
                    ),
                  ),
                const SizedBox(height: 8),
                const Text('Classifique suas categorias:'),
                const SizedBox(height: 8),
                ...categories.map((cat) {
                  final current = typeMap[cat] ?? 'variable';
                  return Card(
                    child: ListTile(
                      title: Text(cat),
                      subtitle: Text('Gasto: ${CurrencyFormats.formatBRL(expenseByCategory[cat] ?? 0)}'),
                      trailing: DropdownButton<String>(
                        value: current,
                        items: const [
                          DropdownMenuItem(value: 'fixed', child: Text('Fixa')),
                          DropdownMenuItem(value: 'variable', child: Text('Variável')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          _types.doc(cat).set({
                            'category': cat,
                            'type': v,
                            'updatedAt': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));
                        },
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }
}

class _PaymentsTab extends StatelessWidget {
  final String uid;
  final DateTime monthStart;
  final DateTime monthEnd;
  const _PaymentsTab({required this.uid, required this.monthStart, required this.monthEnd});

  CollectionReference<Map<String, dynamic>> get _payments =>
      FirebaseFirestore.instance.collection('users').doc(firestoreUserDocIdForAppShell(uid)).collection('payments');

  Future<void> _addPayment(BuildContext context) async {
    final descCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    DateTime due = DateTime.now().add(const Duration(days: 7));

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Novo pagamento'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            FastTextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Descrição')),
            const SizedBox(height: 10),
            BrlAmountTextField(
              controller: amountCtrl,
              decoration: const InputDecoration(labelText: 'Valor'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: Text('Vencimento: ${due.day.toString().padLeft(2, '0')}/${due.month.toString().padLeft(2, '0')}/${due.year}')),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: due,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => due = picked);
                  },
                  child: const Text('Alterar'),
                ),
              ],
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final amount = CurrencyFormats.parseBRLInput(amountCtrl.text) ?? 0;
    final desc = descCtrl.text.trim();
    if (desc.isEmpty || amount <= 0) return;

    await _payments.add({
      'description': desc,
      'amount': amount,
      'dueDate': Timestamp.fromDate(due),
      'paid': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final next30 = now.add(const Duration(days: 30));

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _payments
          .where('dueDate', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
          .where('dueDate', isLessThanOrEqualTo: Timestamp.fromDate(next30))
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.event),
              label: const Text('Adicionar pagamento'),
              onPressed: () => _addPayment(context),
            ),
            const SizedBox(height: 12),
            if (docs.isEmpty)
              const Center(child: Text('Nenhum pagamento nos próximos 30 dias.')),
            ...docs.map((doc) {
              final d = doc.data();
              final due = (d['dueDate'] as Timestamp?)?.toDate() ?? DateTime.now();
              final paid = (d['paid'] ?? false) as bool;

              return Card(
                child: ListTile(
                  title: Text(d['description'] ?? ''),
                  subtitle: Text('Vence em ${due.day.toString().padLeft(2, '0')}/${due.month.toString().padLeft(2, '0')}/${due.year} • ${CurrencyFormats.formatBRL((d['amount'] ?? 0).toDouble())}'),
                  trailing: Checkbox(
                    value: paid,
                    onChanged: (v) {
                      doc.reference.set({
                        'paid': v ?? false,
                        'paidAt': (v ?? false) ? FieldValue.serverTimestamp() : null,
                      }, SetOptions(merge: true));
                    },
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _SimulatorTab extends StatefulWidget {
  final String uid;
  final DateTime monthStart;
  final DateTime monthEnd;
  const _SimulatorTab({required this.uid, required this.monthStart, required this.monthEnd});

  @override
  State<_SimulatorTab> createState() => _SimulatorTabState();
}

class _SimulatorTabState extends State<_SimulatorTab> {
  final TextEditingController _reduceAmount = TextEditingController();
  final TextEditingController _increaseIncome = TextEditingController();
  final TextEditingController _anticipate = TextEditingController();
  Timer? _simDebounce;

  CollectionReference<Map<String, dynamic>> get _tx =>
      FirebaseFirestore.instance.collection('users').doc(firestoreUserDocIdForAppShell(widget.uid)).collection('transactions');
  CollectionReference<Map<String, dynamic>> get _payments =>
      FirebaseFirestore.instance.collection('users').doc(firestoreUserDocIdForAppShell(widget.uid)).collection('payments');

  void _onSimFieldChanged() {
    _simDebounce?.cancel();
    _simDebounce = Timer(
      Duration(milliseconds: AppBusinessRules.searchDebounceMs),
      () {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _simDebounce?.cancel();
    _reduceAmount.dispose();
    _increaseIncome.dispose();
    _anticipate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final txStream = _tx
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(widget.monthStart))
        .where('date', isLessThan: Timestamp.fromDate(widget.monthEnd))
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: txStream,
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        double income = 0;
        double expense = 0;
        for (final doc in snap.data!.docs) {
          final d = doc.data();
          final amount = (d['amount'] ?? 0).toDouble();
          if (d['type'] == 'income') income += amount;
          if (d['type'] == 'expense') expense += amount;
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _payments
              .where('dueDate', isGreaterThanOrEqualTo: Timestamp.fromDate(widget.monthStart))
              .where('dueDate', isLessThan: Timestamp.fromDate(widget.monthEnd))
              .snapshots(),
          builder: (context, paySnap) {
            final payments = paySnap.data?.docs ?? [];
            final planned = payments.fold<double>(0, (total, d) {
              final data = d.data();
              final paid = (data['paid'] ?? false) as bool;
              if (paid) return total;
              return total + ((data['amount'] ?? 0).toDouble());
            });

            final base = income - expense - planned;
            final reduce = CurrencyFormats.parseBRLInput(_reduceAmount.text) ?? 0;
            final increase = CurrencyFormats.parseBRLInput(_increaseIncome.text) ?? 0;
            final anticipate = CurrencyFormats.parseBRLInput(_anticipate.text) ?? 0;
            final simulated = base + reduce + increase - anticipate;

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.auto_graph),
                    title: Text('Saldo base do mês: ${CurrencyFormats.formatBRL(base)}'),
                    subtitle: const Text('Use o simulador para testar cenários.'),
                  ),
                ),
                const SizedBox(height: 8),
                BrlAmountTextField(
                  controller: _reduceAmount,
                  decoration: const InputDecoration(labelText: 'Reduzir gasto (R\$) em categoria'),
                  onChanged: (_) => _onSimFieldChanged(),
                ),
                const SizedBox(height: 8),
                BrlAmountTextField(
                  controller: _increaseIncome,
                  decoration: const InputDecoration(labelText: 'Aumentar receita (R\$)'),
                  onChanged: (_) => _onSimFieldChanged(),
                ),
                const SizedBox(height: 8),
                BrlAmountTextField(
                  controller: _anticipate,
                  decoration: const InputDecoration(labelText: 'Antecipar parcela/pagamento (R\$)'),
                  onChanged: (_) => _onSimFieldChanged(),
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text('Saldo simulado: ${CurrencyFormats.formatBRL(simulated)}'),
                    subtitle: const Text('Impacto estimado com base nos lançamentos atuais.'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
