import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'fast_text_field.dart';

import '../constants/currency_formats.dart';
import '../constants/date_time_formats.dart';
import '../constants/finance_account_visuals.dart';
import '../models/finance_account.dart';
import '../models/user_profile.dart';
import '../services/finance_transfer_service.dart';
import '../services/functions_service.dart';
import '../services/logs_service.dart';
import '../theme/app_colors.dart';
import '../screens/anexo_viewer_screen.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/keyboard_form_scaffold.dart';
import '../utils/premium_upgrade.dart';
import 'brl_amount_text_field.dart';
import 'finance_bank_brand_thumb.dart';
import 'finance_premium_ui.dart';
import '../utils/finance_transaction_datetime.dart';

const List<String> _kTransferReceiptExtensions = ['pdf', 'png', 'jpg', 'jpeg'];

/// Dados preenchidos na tela de transferência.
class FinanceTransferSheetResult {
  final double amount;
  final String fromId;
  final String toId;
  final DateTime selectedCalendarDay;
  final String note;
  final Uint8List? receiptBytes;
  final String? receiptName;
  final String? receiptMime;

  const FinanceTransferSheetResult({
    required this.amount,
    required this.fromId,
    required this.toId,
    required this.selectedCalendarDay,
    required this.note,
    this.receiptBytes,
    this.receiptName,
    this.receiptMime,
  });

  bool get hasReceipt =>
      receiptBytes != null &&
      receiptBytes!.isNotEmpty &&
      (receiptName ?? '').trim().isNotEmpty &&
      (receiptMime ?? '').trim().isNotEmpty;
}

/// API legada — abre tela cheia premium (teclado rápido, valor sempre visível).
class FinanceTransferBottomSheet extends StatelessWidget {
  final List<FinanceAccount> accounts;
  final String initialFromId;
  final String initialToId;

  const FinanceTransferBottomSheet({
    super.key,
    required this.accounts,
    required this.initialFromId,
    required this.initialToId,
  });

  static Future<FinanceTransferSheetResult?> show(
    BuildContext context, {
    required List<FinanceAccount> accounts,
    required String initialFromId,
    required String initialToId,
  }) {
    return Navigator.of(context).push<FinanceTransferSheetResult>(
      MaterialPageRoute<FinanceTransferSheetResult>(
        fullscreenDialog: true,
        builder: (_) => FinanceTransferBottomSheet(
          accounts: accounts,
          initialFromId: initialFromId,
          initialToId: initialToId,
        ),
      ),
    );
  }

  static Future<bool> showEdit(
    BuildContext context, {
    required String uid,
    required UserProfile profile,
    required String pairId,
    required List<FinanceAccount> accounts,
    String logModulo = 'Financeiro',
  }) =>
      _FinanceTransferEdit.show(
        context,
        uid: uid,
        profile: profile,
        pairId: pairId,
        accounts: accounts,
        logModulo: logModulo,
      );

  @override
  Widget build(BuildContext context) {
    return _FinanceTransferPage(
      accounts: accounts,
      initialFromId: initialFromId,
      initialToId: initialToId,
    );
  }
}

class _FinanceTransferPage extends StatefulWidget {
  final List<FinanceAccount> accounts;
  final String initialFromId;
  final String initialToId;

  const _FinanceTransferPage({
    required this.accounts,
    required this.initialFromId,
    required this.initialToId,
  });

  @override
  State<_FinanceTransferPage> createState() => _FinanceTransferPageState();
}

class _FinanceTransferPageState extends State<_FinanceTransferPage> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  late final FocusNode _amountFocus;
  late DateTime _transferDay;
  late String _fromId;
  late String _toId;
  bool _submitting = false;
  bool _hasReceipt = false;
  Uint8List? _receiptBytes;
  String _receiptName = '';
  String? _receiptMime;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController();
    _noteCtrl = TextEditingController();
    _amountFocus = FocusNode();
    _transferDay = DateTime.now();
    _fromId = widget.initialFromId;
    _toId = widget.initialToId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _amountFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  FinanceAccount _acc(String id) => widget.accounts.firstWhere((a) => a.id == id);

  Future<void> _pickReceipt() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _kTransferReceiptExtensions,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.single;
      final ext = (f.extension ?? '').toLowerCase();
      if (!_kTransferReceiptExtensions.contains(ext) && ext != 'jpeg') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Arquivo inválido. Use JPEG, PNG ou PDF.')),
          );
        }
        return;
      }
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Não foi possível ler o arquivo. Tente outro.')),
          );
        }
        return;
      }
      if (bytes.lengthInBytes > 5 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Arquivo grande demais. Limite: 5 MB.')),
          );
        }
        return;
      }
      final mime = ext == 'pdf' ? 'application/pdf' : (ext == 'png' ? 'image/png' : 'image/jpeg');
      setState(() {
        _hasReceipt = true;
        _receiptBytes = bytes;
        _receiptName = f.name;
        _receiptMime = mime;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao selecionar arquivo: ${e.toString().split('\n').first}')),
        );
      }
    }
  }

  Widget _buildReceiptPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Comprovante (JPEG, PNG ou PDF)',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF1A237E)),
        ),
        const SizedBox(height: 8),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _pickReceipt,
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _hasReceipt ? AppColors.primary.withValues(alpha: 0.45) : const Color(0xFFE2E8F0),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _hasReceipt ? Icons.check_circle_rounded : Icons.attach_file_rounded,
                    color: _hasReceipt ? AppColors.financeReceita : AppColors.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _hasReceipt ? _receiptName : 'Toque para anexar comprovante',
                      style: TextStyle(
                        fontWeight: _hasReceipt ? FontWeight.w700 : FontWeight.w600,
                        fontSize: 13.5,
                        color: _hasReceipt ? AppColors.textPrimary : AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_hasReceipt)
                    IconButton(
                      tooltip: 'Remover comprovante',
                      onPressed: () => setState(() {
                        _hasReceipt = false;
                        _receiptBytes = null;
                        _receiptName = '';
                        _receiptMime = null;
                      }),
                      icon: Icon(Icons.close_rounded, color: Colors.grey.shade600),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickAccount({
    required String title,
    required String selectedId,
    required Set<String> excludeIds,
    required ValueChanged<String> onPicked,
  }) async {
    final items = widget.accounts.where((a) => !excludeIds.contains(a.id)).toList();
    if (items.isEmpty) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.paddingOf(ctx).bottom;
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: EdgeInsets.only(bottom: bottom),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: AppColors.deepBlueDark.withValues(alpha: 0.15),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.45),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final a = items[i];
                    final vis = financeAccountVisualFor(a);
                    final sel = a.id == selectedId;
                    return ListTile(
                      leading: _TransferAccountThumb(account: a),
                      title: Text(a.displayName, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(vis.badgeLabel, style: TextStyle(fontSize: 12, color: vis.isCreditCardStyle ? const Color(0xFF4F46E5) : AppColors.textMuted)),
                      trailing: sel ? Icon(Icons.check_circle_rounded, color: AppColors.primary) : null,
                      onTap: () => Navigator.pop(ctx, a.id),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked != null && mounted) onPicked(picked);
  }

  void _submit() {
    if (_submitting) return;
    final value = CurrencyFormats.parseBRLInput(_amountCtrl.text) ?? 0;
    if (value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe um valor válido.')));
      return;
    }
    if (_fromId == _toId) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Origem e destino devem ser contas diferentes.')));
      return;
    }
    Navigator.pop(
      context,
      FinanceTransferSheetResult(
        amount: value,
        fromId: _fromId,
        toId: _toId,
        selectedCalendarDay: _transferDay,
        note: _noteCtrl.text.trim(),
        receiptBytes: _hasReceipt ? _receiptBytes : null,
        receiptName: _hasReceipt ? _receiptName : null,
        receiptMime: _hasReceipt ? _receiptMime : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fromAcc = _acc(_fromId);
    final toAcc = _acc(_toId);

    return Scaffold(
      resizeToAvoidBottomInset: scaffoldKeyboardResizeToAvoidBottomInset(standaloneFullPageForm: true),
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: financePremiumGradientAppBar(
        title: 'Transferência',
        onBack: () => Navigator.pop(context),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Saída na origem e entrada no destino — histórico em ambas as contas.',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textMuted.withValues(alpha: 0.95), height: 1.35),
            ),
          ),
          // Valor fixo no topo — não some com o teclado.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: RepaintBoundary(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.14),
                      AppColors.accent.withValues(alpha: 0.1),
                      Colors.white,
                    ],
                  ),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.28), width: 1.4),
                  boxShadow: [
                    BoxShadow(color: AppColors.primary.withValues(alpha: 0.1), blurRadius: 16, offset: const Offset(0, 6)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.payments_rounded, color: AppColors.primary, size: 22),
                        const SizedBox(width: 8),
                        const Text('Valor da transferência', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          'R\$',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: BrlAmountTextField(
                            controller: _amountCtrl,
                            focusNode: _amountFocus,
                            scrollPadding: KeyboardFormInsets.fieldScrollPadding(
                              context,
                              footerEstimate: 120,
                              standaloneFullPageForm: true,
                            ),
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                            ),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              hintText: '0,00',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                _TransferAccountPickerTile(
                  label: 'Conta de origem (saída)',
                  account: fromAcc,
                  accent: AppColors.financeDespesa,
                  icon: Icons.north_east_rounded,
                  onTap: () => _pickAccount(
                    title: 'Conta de origem',
                    selectedId: _fromId,
                    excludeIds: {_toId},
                    onPicked: (v) => setState(() {
                      _fromId = v;
                      if (_fromId == _toId) {
                        final alt = widget.accounts.where((a) => a.id != _fromId).toList();
                        if (alt.isNotEmpty) _toId = alt.first.id;
                      }
                    }),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [AppColors.primary.withValues(alpha: 0.15), AppColors.accent.withValues(alpha: 0.12)]),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_downward_rounded, color: AppColors.primary, size: 22),
                    ),
                  ),
                ),
                _TransferAccountPickerTile(
                  label: 'Conta de destino (entrada)',
                  account: toAcc,
                  accent: AppColors.financeReceita,
                  icon: Icons.south_west_rounded,
                  onTap: () => _pickAccount(
                    title: 'Conta de destino',
                    selectedId: _toId,
                    excludeIds: {_fromId},
                    onPicked: (v) => setState(() => _toId = v),
                  ),
                ),
                const SizedBox(height: 14),
                FinancePremiumFieldTile(
                  label: 'Data do lançamento',
                  value: DateTimeFormats.dateBR.format(_transferDay),
                  icon: Icons.calendar_month_rounded,
                  accent: AppColors.primary,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _transferDay,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _transferDay = picked);
                  },
                ),
                const SizedBox(height: 12),
                FastTextField(
                  controller: _noteCtrl,
                  maxLines: 2,
                  minLines: 1,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Observação (opcional)',
                    hintText: 'Ex.: resgate, pagamento de cartão',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: 14),
                _buildReceiptPicker(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: KeyboardAwareFormBar(
        standaloneFullPageForm: true,
        child: FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.swap_horiz_rounded, size: 22),
          label: const Text('Transferir', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
    );
  }
}

class _TransferAccountThumb extends StatelessWidget {
  final FinanceAccount account;

  const _TransferAccountThumb({required this.account});

  @override
  Widget build(BuildContext context) {
    final vis = financeAccountVisualFor(account);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(colors: vis.gradient.length >= 2 ? vis.gradient.sublist(0, 2) : vis.gradient),
        border: vis.isCreditCardStyle ? Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.55)) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (vis.isCreditCardStyle) const FinanceCreditCardPattern(),
          Center(
            child: FinanceBankBrandThumb(
              preset: account.preset,
              size: 28,
              onBrandGradient: true,
              fallbackIcon: vis.icon,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferAccountPickerTile extends StatelessWidget {
  final String label;
  final FinanceAccount account;
  final Color accent;
  final IconData icon;
  final VoidCallback onTap;

  const _TransferAccountPickerTile({
    required this.label,
    required this.account,
    required this.accent,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final vis = financeAccountVisualFor(account);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white,
            border: Border.all(color: accent.withValues(alpha: 0.28)),
            boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 52,
                  decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(width: 12),
                _TransferAccountThumb(account: account),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: accent)),
                      const SizedBox(height: 2),
                      Text(account.displayName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                      Text(vis.badgeLabel, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: vis.isCreditCardStyle ? const Color(0xFF4F46E5) : AppColors.textMuted)),
                    ],
                  ),
                ),
                Icon(Icons.arrow_drop_down_circle_outlined, color: accent.withValues(alpha: 0.75)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FinanceTransferEdit {
  _FinanceTransferEdit._();

  static Future<bool> show(
    BuildContext context, {
    required String uid,
    required UserProfile profile,
    required String pairId,
    required List<FinanceAccount> accounts,
    String logModulo = 'Financeiro',
  }) async {
    if (!profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, profile);
      return false;
    }
    if (accounts.length < 2) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cadastre ao menos duas contas para editar a transferência.')),
        );
      }
      return false;
    }

    Map<String, dynamic>? pairData;
    try {
      pairData = await FunctionsService().getFinanceTransferPair(pairId: pairId);
    } catch (_) {
      final fsUid = firestoreUserDocIdForAppShell(uid);
      final pairSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(fsUid)
          .collection('transactions')
          .where('transferPairId', isEqualTo: pairId)
          .get();
      if (pairSnap.docs.length < 2 || !context.mounted) return false;
      DocumentSnapshot<Map<String, dynamic>>? outDoc;
      DocumentSnapshot<Map<String, dynamic>>? inDoc;
      for (final d in pairSnap.docs) {
        final dir = (d.data()['transferDirection'] ?? '').toString();
        if (dir == 'out') outDoc = d;
        if (dir == 'in') inDoc = d;
      }
      outDoc ??= pairSnap.docs.first;
      inDoc ??= pairSnap.docs.last;
      final outData = outDoc.data() ?? {};
      final date = (outData['date'] as Timestamp?)?.toDate() ?? DateTime.now();
      pairData = {
        'amount': (outData['amount'] ?? 0).toDouble().abs(),
        'fromAccountId': (outDoc.data()?['financeAccountId'] ?? '').toString(),
        'toAccountId': (inDoc.data()?['financeAccountId'] ?? '').toString(),
        'dateISO': date.toIso8601String(),
        'note': '',
        'outId': outDoc.id,
        'inId': inDoc.id,
      };
    }
    if (!context.mounted || pairData == null) return false;

    final fsUid = firestoreUserDocIdForAppShell(uid);
    var receiptLink = '';
    final outIdForReceipt = (pairData['outId'] ?? '').toString();
    if (outIdForReceipt.isNotEmpty) {
      final outSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(fsUid)
          .collection('transactions')
          .doc(outIdForReceipt)
          .get();
      final receipt = Map<String, dynamic>.from(outSnap.data()?['receipt'] ?? {});
      receiptLink = (receipt['webViewLink'] ?? receipt['webContentLink'] ?? receipt['downloadUrl'] ?? '').toString();
    }

    final amountCtrl = TextEditingController(text: CurrencyFormats.formatBRLInput((pairData['amount'] as num).toDouble()));
    final noteCtrl = TextEditingController(text: (pairData['note'] ?? '').toString());
    var transferDay = DateTime.tryParse((pairData['dateISO'] ?? '').toString()) ?? DateTime.now();
    transferDay = DateTime(transferDay.year, transferDay.month, transferDay.day);
    var editFromId = (pairData['fromAccountId'] ?? '').toString();
    var editToId = (pairData['toAccountId'] ?? '').toString();
    if (!accounts.any((a) => a.id == editFromId)) editFromId = accounts.first.id;
    if (!accounts.any((a) => a.id == editToId)) editToId = accounts.length > 1 ? accounts[1].id : accounts.first.id;
    var removeReceipt = false;
    Uint8List? newReceiptBytes;
    var newReceiptName = '';
    String? newReceiptMime;

    final ok = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.deepBlueDark.withValues(alpha: 0.55),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.9),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(colors: [Color(0xFFF8FAFC), Colors.white]),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: AppColors.logoGradient),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text('Editar transferência', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                          ),
                          IconButton(onPressed: () => Navigator.pop(ctx, false), icon: const Icon(Icons.close_rounded, color: Colors.white)),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Text(
                                  'R\$',
                                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textSecondary),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: BrlAmountTextField(
                                    controller: amountCtrl,
                                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                                    decoration: InputDecoration(
                                      labelText: 'Valor',
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            DropdownButtonFormField<String>(
                              value: editFromId,
                              decoration: const InputDecoration(labelText: 'Conta de origem (saída)', border: OutlineInputBorder()),
                              items: accounts.where((a) => a.id != editToId).map((a) => DropdownMenuItem(value: a.id, child: Text(a.displayName))).toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() => editFromId = v);
                              },
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              value: editToId,
                              decoration: const InputDecoration(labelText: 'Conta de destino (entrada)', border: OutlineInputBorder()),
                              items: accounts.where((a) => a.id != editFromId).map((a) => DropdownMenuItem(value: a.id, child: Text(a.displayName))).toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() => editToId = v);
                              },
                            ),
                            const SizedBox(height: 10),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Data'),
                              subtitle: Text(DateTimeFormats.dateBR.format(transferDay)),
                              trailing: TextButton(
                                onPressed: () async {
                                  final picked = await showDatePicker(context: context, initialDate: transferDay, firstDate: DateTime(2020), lastDate: DateTime(2100));
                                  if (picked != null) setState(() => transferDay = picked);
                                },
                                child: const Text('Alterar'),
                              ),
                            ),
                            FastTextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Observação (opcional)', border: OutlineInputBorder())),
                            const SizedBox(height: 14),
                            const Divider(),
                            const Text('Comprovante', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                            const SizedBox(height: 8),
                            if (receiptLink.trim().isNotEmpty && !removeReceipt && newReceiptBytes == null)
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.visibility_rounded, size: 18),
                                      label: const Text('Ver anexo'),
                                      onPressed: () async {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) => AnexoViewerScreen(url: receiptLink, fileName: 'Comprovante'),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                    label: const Text('Remover'),
                                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                                    onPressed: () => setState(() {
                                      removeReceipt = true;
                                      newReceiptBytes = null;
                                    }),
                                  ),
                                ],
                              ),
                            OutlinedButton.icon(
                              icon: Icon(
                                (receiptLink.trim().isNotEmpty && !removeReceipt) || newReceiptBytes != null
                                    ? Icons.swap_horiz_rounded
                                    : Icons.attach_file_rounded,
                                size: 18,
                              ),
                              label: Text(
                                (receiptLink.trim().isNotEmpty && !removeReceipt) || newReceiptBytes != null
                                    ? 'Trocar comprovante'
                                    : 'Anexar comprovante (PDF, PNG, JPG)',
                              ),
                              onPressed: () async {
                                final pick = await FilePicker.platform.pickFiles(
                                  type: FileType.custom,
                                  allowedExtensions: _kTransferReceiptExtensions,
                                  withData: true,
                                );
                                if (pick == null || pick.files.isEmpty) return;
                                final f = pick.files.first;
                                final bytes = f.bytes ?? Uint8List(0);
                                final ext = (f.extension ?? '').toLowerCase();
                                if (!_kTransferReceiptExtensions.contains(ext)) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Use PDF, PNG ou JPG.')),
                                    );
                                  }
                                  return;
                                }
                                if (bytes.lengthInBytes > 5 * 1024 * 1024) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Arquivo grande. Máx. 5 MB.')),
                                    );
                                  }
                                  return;
                                }
                                setState(() {
                                  removeReceipt = false;
                                  newReceiptBytes = bytes;
                                  newReceiptName = f.name;
                                  newReceiptMime = ext == 'pdf'
                                      ? 'application/pdf'
                                      : (ext == 'png' ? 'image/png' : 'image/jpeg');
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + MediaQuery.paddingOf(ctx).bottom),
                      child: Row(
                        children: [
                          Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar'))),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                              child: const Text('Salvar', style: TextStyle(fontWeight: FontWeight.w900)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (ok != true || !context.mounted) {
      amountCtrl.dispose();
      noteCtrl.dispose();
      return false;
    }

    final newAmount = CurrencyFormats.parseBRLInput(amountCtrl.text) ?? 0;
    if (newAmount <= 0 || editFromId == editToId) {
      amountCtrl.dispose();
      noteCtrl.dispose();
      return false;
    }

    final col = FirebaseFirestore.instance.collection('users').doc(fsUid).collection('transactions');
    final pairSnap = await col.where('transferPairId', isEqualTo: pairId).get();
    final legIds = pairSnap.docs.map((d) => d.id).toList();
    final fromAcc = accounts.firstWhere((a) => a.id == editFromId);
    final toAcc = accounts.firstWhere((a) => a.id == editToId);
    final histLine = '${fromAcc.displayName} → ${toAcc.displayName}';
    final notePart = noteCtrl.text.trim().isEmpty ? '' : ' • ${noteCtrl.text.trim()}';
    final existingDate = (pairSnap.docs.first.data()['date'] as Timestamp?)?.toDate() ?? DateTime.now();
    final transferAt = FinanceTransactionDatetime.mergeCalendarDayWithExistingTime(transferDay, existingDate);
    final transferTs = Timestamp.fromDate(transferAt);

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in pairSnap.docs) {
      final dir = (doc.data()['transferDirection'] ?? '').toString();
      final isOut = dir == 'out';
      batch.update(doc.reference, {
        'amount': newAmount,
        'date': transferTs,
        'paidAt': transferTs,
        'effectiveDate': transferTs,
        'financeAccountId': isOut ? editFromId : editToId,
        'transferCounterpartyAccountId': isOut ? editToId : editFromId,
        'transferCounterpartyLabel': isOut ? toAcc.displayName : fromAcc.displayName,
        'description': isOut ? 'Saída • Transferência • $histLine$notePart' : 'Entrada • Transferência • $histLine$notePart',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    try {
      await batch.commit();
      if (removeReceipt) {
        await FinanceTransferService.instance.removeReceiptFromTransferLegs(uid: uid, docIds: legIds);
      }
      if (newReceiptBytes != null &&
          newReceiptBytes!.isNotEmpty &&
          newReceiptName.trim().isNotEmpty &&
          (newReceiptMime ?? '').trim().isNotEmpty) {
        await FinanceTransferService.instance.attachReceiptToTransferLegs(
          uid: uid,
          docIds: legIds,
          bytes: newReceiptBytes!,
          name: newReceiptName,
          mime: newReceiptMime!,
        );
      }
      if (context.mounted) {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transferência atualizada.')));
      }
      unawaited(LogsService().saveLog(modulo: logModulo, acao: 'Editou transferência', detalhes: '$histLine • ${CurrencyFormats.formatBRL(newAmount)}').catchError((_) {}));
      amountCtrl.dispose();
      noteCtrl.dispose();
      return true;
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: ${err.toString().split('\n').first}'), backgroundColor: AppColors.error));
      }
      amountCtrl.dispose();
      noteCtrl.dispose();
      return false;
    }
  }
}
