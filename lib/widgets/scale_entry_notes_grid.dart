import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/field_text_limits.dart';
import '../theme/app_colors.dart';
import '../theme/gemini_theme.dart';
import '../utils/keyboard_form_scaffold.dart';
import '../utils/scale_entry_sei_ocorrencia.dart';
import '../utils/uppercase_text_input_formatter.dart';
import 'agenda_form_footer_actions.dart';
import 'fast_text_field.dart';

/// Bloco de observação nos cards da grid Escalas: prévia, «Veja mais» (200 chars) e olho (preview editável).
class ScaleEntryNotesGridBlock extends StatefulWidget {
  const ScaleEntryNotesGridBlock({
    super.key,
    required this.notes,
    required this.entryTitle,
    required this.onSaveNotes,
    this.fontSize = 13,
    this.showObsPrefix = false,
  });

  final String notes;
  final String entryTitle;
  final Future<bool> Function(String notes) onSaveNotes;
  final double fontSize;
  final bool showObsPrefix;

  @override
  State<ScaleEntryNotesGridBlock> createState() =>
      _ScaleEntryNotesGridBlockState();
}

class _ScaleEntryNotesGridBlockState extends State<ScaleEntryNotesGridBlock> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant ScaleEntryNotesGridBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notes.trim() != widget.notes.trim()) {
      _expanded = false;
    }
  }

  String get _trimmed => widget.notes.trim();

  bool get _canExpand => _trimmed.length > kScaleNotesGridCollapsedChars;

  String get _displayText {
    if (_trimmed.isEmpty) return '';
    if (!_expanded) {
      if (_trimmed.length <= kScaleNotesGridCollapsedChars) return _trimmed;
      return '${_trimmed.substring(0, kScaleNotesGridCollapsedChars)}…';
    }
    if (_trimmed.length <= kScaleNotesGridExpandChars) return _trimmed;
    return '${_trimmed.substring(0, kScaleNotesGridExpandChars)}…';
  }

  Future<void> _openPreview() async {
    final saved = await ScaleNotesPreviewSheet.show(
      context,
      initialNotes: _trimmed,
      entryTitle: widget.entryTitle,
      onSave: widget.onSaveNotes,
    );
    if (saved && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_trimmed.isEmpty) return const SizedBox.shrink();

    final prefix = widget.showObsPrefix ? 'Obs: ' : '';

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '$prefix$_displayText',
                  style: TextStyle(
                    fontSize: widget.fontSize,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Material(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: _openPreview,
                  borderRadius: BorderRadius.circular(10),
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(
                      Icons.visibility_outlined,
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_canExpand)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                ),
                label: Text(
                  _expanded
                      ? 'Ver menos'
                      : 'Veja mais (${kScaleNotesGridExpandChars} iniciais)',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Preview moderno da observação completa — editável e salva no Firestore.
class ScaleNotesPreviewSheet {
  ScaleNotesPreviewSheet._();

  static Future<bool> show(
    BuildContext context, {
    required String initialNotes,
    required String entryTitle,
    required Future<bool> Function(String notes) onSave,
  }) async {
    final result = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        settings: const RouteSettings(name: '/escalas/observacao-preview'),
        builder: (_) => _ScaleNotesPreviewPage(
          initialNotes: initialNotes,
          entryTitle: entryTitle,
          onSave: onSave,
        ),
      ),
    );
    return result == true;
  }
}

class _ScaleNotesPreviewPage extends StatefulWidget {
  const _ScaleNotesPreviewPage({
    required this.initialNotes,
    required this.entryTitle,
    required this.onSave,
  });

  final String initialNotes;
  final String entryTitle;
  final Future<bool> Function(String notes) onSave;

  @override
  State<_ScaleNotesPreviewPage> createState() => _ScaleNotesPreviewPageState();
}

class _ScaleNotesPreviewPageState extends State<_ScaleNotesPreviewPage> {
  late final TextEditingController _ctrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialNotes);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final ok = await widget.onSave(_ctrl.text);
      if (ok && mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final clip = (data?.text ?? '').trim();
    if (clip.isEmpty) return;
    final merged = '${_ctrl.text}$clip';
    _ctrl.text = normalizeScaleNotesForSave(merged);
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: scaffoldKeyboardResizeToAvoidBottomInset(
        standaloneFullPageForm: true,
      ),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: AppColors.logoGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: const Text(
          'Observações',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Material(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.work_history_rounded,
                      size: 22,
                      color: AppColors.primary.withValues(alpha: 0.9),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.entryTitle.isEmpty
                                ? 'Plantão'
                                : widget.entryTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: AppColors.deepBlueDark,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Até $kScaleNotesMaxLength caracteres · editável',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMuted.withValues(alpha: 0.95),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Material(
                elevation: 0,
                color: Colors.white,
                borderRadius: BorderRadius.circular(GeminiTheme.cardRadius),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(GeminiTheme.cardRadius),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.15),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  child: FastTextField(
                    controller: _ctrl,
                    minLines: 12,
                    maxLines: 24,
                    maxLength: kScaleNotesMaxLength,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [UpperCaseTextFormatter()],
                    kind: FastTextFieldKind.prose,
                    scrollPadding: KeyboardFormInsets.fieldScrollPadding(
                      context,
                      standaloneFullPageForm: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Observações completas',
                      hintText: 'DETALHES DO PLANTÃO',
                      border: InputBorder.none,
                      alignLabelWithHint: true,
                      suffixIcon: IconButton(
                        tooltip: 'Colar',
                        onPressed: _paste,
                        icon: const Icon(Icons.content_paste_rounded, size: 20),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          AgendaFormFooterActions(
            onCancel: () => Navigator.of(context).pop(false),
            onSave: () => _save(),
            saveLabel: 'Salvar',
            isBusy: _saving,
            saveIcon: Icons.save_rounded,
          ),
        ],
      ),
    );
  }
}
