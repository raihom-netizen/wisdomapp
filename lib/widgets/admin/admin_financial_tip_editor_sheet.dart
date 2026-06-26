import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../constants/currency_formats.dart';
import '../../models/finance_tip_bank_entry.dart';
import '../../theme/app_colors.dart';
import '../../utils/insights_engine.dart';
import '../../widgets/fast_text_field.dart';
import '../../widgets/shell_keyboard_bottom_pad.dart';

/// Editor moderno de dica financeira (criar / editar).
class AdminFinancialTipEditorSheet {
  static const iconKeys = [
    'lightbulb',
    'menu_book',
    'savings',
    'warning',
    'credit_card',
    'trending_up',
    'bar_chart',
    'timer',
    'percent',
    'account_balance',
    'directions_car',
    'money_off',
    'subscriptions',
    'shield',
    'search',
    'fastfood',
  ];

  static const colorKeys = [
    'primary',
    'blue',
    'green',
    'teal',
    'indigo',
    'purple',
    'orange',
    'red',
    'deepOrange',
    'blueGrey',
  ];

  static const condicaoTipos = [
    'sempre',
    'gasto_maior_receita',
    'categoria_maior',
    'concentracao_categoria',
  ];

  static Future<bool?> show(
    BuildContext context, {
    required CollectionReference<Map<String, dynamic>> col,
    QueryDocumentSnapshot<Map<String, dynamic>>? existing,
    bool biblicalMode = false,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditorBody(
        col: col,
        existing: existing,
        biblicalMode: biblicalMode,
      ),
    );
  }
}

class _EditorBody extends StatefulWidget {
  const _EditorBody({
    required this.col,
    this.existing,
    required this.biblicalMode,
  });

  final CollectionReference<Map<String, dynamic>> col;
  final QueryDocumentSnapshot<Map<String, dynamic>>? existing;
  final bool biblicalMode;

  @override
  State<_EditorBody> createState() => _EditorBodyState();
}

class _EditorBodyState extends State<_EditorBody> {
  late final TextEditingController _tituloCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _categoriaCtrl;
  late final TextEditingController _referenciaCtrl;
  late final TextEditingController _versiculoCtrl;
  late final TextEditingController _ordemCtrl;
  late final TextEditingController _catCondCtrl;
  late final TextEditingController _valorMinCtrl;
  late final TextEditingController _pctMinCtrl;

  late String _iconKey;
  late String _colorKey;
  late bool _ativo;
  late bool _favorita;
  late bool _exibirNoInicio;
  late String _tipoCond;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.existing?.data() ?? {};
    _tituloCtrl = TextEditingController(text: (d['titulo'] ?? '').toString());
    _descCtrl = TextEditingController(text: (d['descricao'] ?? '').toString());
    _categoriaCtrl = TextEditingController(
      text: (d['categoria'] ?? '').toString().isNotEmpty
          ? (d['categoria'] ?? '').toString()
          : (widget.biblicalMode ? 'biblia' : ''),
    );
    _referenciaCtrl = TextEditingController(
      text: (d['referenciaBiblica'] ?? d['versiculo'] ?? '').toString(),
    );
    _versiculoCtrl = TextEditingController(
      text: (d['textoVersiculo'] ?? d['versiculoTexto'] ?? d['citacao'] ?? '').toString(),
    );
    _ordemCtrl = TextEditingController(text: '${d['ordem'] ?? 10}');
    _catCondCtrl = TextEditingController();
    _valorMinCtrl = TextEditingController();
    _pctMinCtrl = TextEditingController();
    _iconKey = (d['icone'] ?? d['iconKey'] ?? (widget.biblicalMode ? 'menu_book' : 'lightbulb'))
        .toString();
    _colorKey = (d['cor'] ?? d['colorKey'] ?? 'primary').toString();
    _ativo = d['ativo'] != false;
    _favorita = d['favorita'] == true;
    _exibirNoInicio = d['exibirNoInicio'] == true;
    _tipoCond = 'sempre';
    final cond = d['condicao'];
    if (cond is Map) {
      _tipoCond = (cond['tipo'] ?? 'sempre').toString();
      _catCondCtrl.text = (cond['categoria'] ?? '').toString();
      if (cond['valor_min'] != null) {
        _valorMinCtrl.text = CurrencyFormats.formatBRLInput((cond['valor_min'] as num).toDouble());
      }
      if (cond['pct_min'] != null) _pctMinCtrl.text = '${cond['pct_min']}';
    }
  }

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _descCtrl.dispose();
    _categoriaCtrl.dispose();
    _referenciaCtrl.dispose();
    _versiculoCtrl.dispose();
    _ordemCtrl.dispose();
    _catCondCtrl.dispose();
    _valorMinCtrl.dispose();
    _pctMinCtrl.dispose();
    super.dispose();
  }

  Color get _accent => kFinanceTipColorByKey[_colorKey] ?? AppColors.primary;

  IconData get _icon => kFinanceTipIconByKey[_iconKey] ?? Icons.lightbulb_outline_rounded;

  InputDecoration _fieldDeco(String label, {String? hint, String? helper}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _accent, width: 2),
      ),
    );
  }

  Future<void> _save() async {
    if (_tituloCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o título da dica.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final ordem = int.tryParse(_ordemCtrl.text.trim()) ?? 10;
      final condicao = <String, dynamic>{'tipo': _tipoCond};
      if (_tipoCond == 'categoria_maior') {
        condicao['categoria'] = _catCondCtrl.text.trim();
        condicao['valor_min'] = CurrencyFormats.parseBRLInput(_valorMinCtrl.text) ?? 0;
      }
      if (_tipoCond == 'concentracao_categoria') {
        condicao['categoria'] = _catCondCtrl.text.trim();
        condicao['pct_min'] = double.tryParse(_pctMinCtrl.text.replaceAll(',', '.')) ?? 0;
      }

      final payload = <String, dynamic>{
        'titulo': _tituloCtrl.text.trim(),
        'descricao': _descCtrl.text.trim(),
        'categoria': _categoriaCtrl.text.trim().isNotEmpty
            ? _categoriaCtrl.text.trim()
            : (widget.biblicalMode ? 'biblia' : 'geral'),
        'referenciaBiblica': _referenciaCtrl.text.trim(),
        'textoVersiculo': _versiculoCtrl.text.trim(),
        'icone': _iconKey,
        'cor': _colorKey,
        'iconKey': _iconKey,
        'colorKey': _colorKey,
        'ordem': ordem,
        'ativo': _ativo,
        'favorita': _favorita,
        'exibirNoInicio': _exibirNoInicio,
        'condicao': condicao,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (widget.existing == null) {
        await widget.col.add(payload);
      } else {
        await widget.existing!.reference.set(payload, SetOptions(merge: true));
      }
      InsightsEngine.clearTipsCache();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom + AppKeyboardInsets.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 0.98,
      builder: (_, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.existing == null ? 'Nova dica' : 'Editar dica',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              _PreviewCard(
                titulo: _tituloCtrl.text,
                referencia: _referenciaCtrl.text,
                versiculo: _versiculoCtrl.text,
                descricao: _descCtrl.text,
                accent: _accent,
                icon: _icon,
              ),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
                  children: [
                    FastTextField(
                      controller: _tituloCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: _fieldDeco('Título'),
                    ),
                    const SizedBox(height: 12),
                    FastTextField(
                      controller: _descCtrl,
                      maxLines: 3,
                      onChanged: (_) => setState(() {}),
                      decoration: _fieldDeco('Descrição / orientação prática'),
                    ),
                    if (widget.biblicalMode) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Versículo bíblico',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _accent,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      FastTextField(
                        controller: _referenciaCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration: _fieldDeco('Referência', hint: 'Ex.: Provérbios 21:20'),
                      ),
                      const SizedBox(height: 12),
                      FastTextField(
                        controller: _versiculoCtrl,
                        maxLines: 3,
                        onChanged: (_) => setState(() {}),
                        decoration: _fieldDeco(
                          'Texto do versículo',
                          helper: 'Aparece em destaque no card do Início.',
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text('Aparência', style: TextStyle(fontWeight: FontWeight.w800, color: _accent)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: AdminFinancialTipEditorSheet.colorKeys.map((k) {
                        final c = kFinanceTipColorByKey[k] ?? AppColors.primary;
                        final sel = _colorKey == k;
                        return ChoiceChip(
                          label: Text(k, style: TextStyle(fontSize: 11, color: sel ? Colors.white : c)),
                          selected: sel,
                          selectedColor: c,
                          backgroundColor: c.withValues(alpha: 0.12),
                          onSelected: (_) => setState(() => _colorKey = k),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: AdminFinancialTipEditorSheet.iconKeys.map((k) {
                        final ic = kFinanceTipIconByKey[k] ?? Icons.lightbulb_outline_rounded;
                        final sel = _iconKey == k;
                        return Material(
                          color: sel ? _accent.withValues(alpha: 0.15) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => setState(() => _iconKey = k),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Icon(ic, color: sel ? _accent : Colors.grey.shade600, size: 22),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    FastTextField(
                      controller: _ordemCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _fieldDeco('Ordem na lista'),
                    ),
                    const SizedBox(height: 8),
                    _modernSwitch('Ativa', _ativo, (v) => setState(() => _ativo = v)),
                    _modernSwitch(
                      'Favorita (dica do dia)',
                      _favorita,
                      (v) => setState(() => _favorita = v),
                      subtitle: 'Rotação diária entre favoritas sincronizadas.',
                    ),
                    _modernSwitch(
                      'Exibir no Início',
                      _exibirNoInicio,
                      (v) => setState(() => _exibirNoInicio = v),
                      subtitle: 'Incluída ao sincronizar para usuários.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(_saving ? 'Salvando…' : 'Salvar dica'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _modernSwitch(
    String title,
    bool value,
    ValueChanged<bool> onChanged, {
    String? subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: subtitle != null
            ? Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
            : null,
        value: value,
        activeTrackColor: _accent.withValues(alpha: 0.5),
        activeThumbColor: _accent,
        onChanged: onChanged,
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.titulo,
    required this.referencia,
    required this.versiculo,
    required this.descricao,
    required this.accent,
    required this.icon,
  });

  final String titulo;
  final String referencia;
  final String versiculo;
  final String descricao;
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [accent, Color.lerp(accent, Colors.black, 0.15)!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo.isEmpty ? 'Pré-visualização' : titulo,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  if (referencia.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      referencia,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12),
                    ),
                  ],
                  if (versiculo.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '"$versiculo"',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ] else if (descricao.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        descricao,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12),
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
}
