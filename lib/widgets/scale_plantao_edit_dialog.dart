import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/scale_entry.dart';
import '../theme/app_colors.dart';
import '../theme/gemini_theme.dart';
import '../utils/keyboard_form_scaffold.dart';
import '../utils/scale_entry_sei_ocorrencia.dart';
import '../utils/uppercase_text_input_formatter.dart';
import 'agenda_form_footer_actions.dart';
import 'fast_text_field.dart';

/// Edição do **nº do plantão** e observações (módulo Escalas).
/// SEI e RAI ficam em Audiências/Compromissos (módulo Agenda).
class ScalePlantaoEditDialog {
  ScalePlantaoEditDialog._();

  static Future<ScalePlantaoEditValues?> show(
    BuildContext context, {
    required ScaleEntry entry,
  }) {
    if (entry.isAgendaMirror) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'SEI e RAI desta audiência/compromisso são editados em '
            'Audiências/Compromissos (módulo Agenda).',
          ),
        ),
      );
      return Future.value(null);
    }

    return Navigator.of(context, rootNavigator: true).push<ScalePlantaoEditValues>(
      MaterialPageRoute<ScalePlantaoEditValues>(
        settings: const RouteSettings(name: '/escalas/editar-numero'),
        builder: (_) => _ScalePlantaoEditPage(entry: entry),
      ),
    );
  }
}

class _ScalePlantaoEditPage extends StatefulWidget {
  const _ScalePlantaoEditPage({required this.entry});

  final ScaleEntry entry;

  @override
  State<_ScalePlantaoEditPage> createState() => _ScalePlantaoEditPageState();
}

class _ScalePlantaoEditPageState extends State<_ScalePlantaoEditPage> {
  late final TextEditingController _scaleCtrl;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = TextEditingController(
      text: scalePlantaoNumberFromEntry(widget.entry),
    );
    _notesCtrl = TextEditingController(text: widget.entry.notes ?? '');
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pasteInto(TextEditingController ctrl, {int? maxLen}) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = (data?.text ?? '').trim();
    if (raw.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nada para colar.')),
        );
      }
      return;
    }
    var txt = raw.toUpperCase();
    if (maxLen != null && txt.length > maxLen) {
      txt = txt.substring(0, maxLen);
    }
    ctrl.text = txt;
    ctrl.selection = TextSelection.collapsed(offset: txt.length);
    setState(() {});
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
    String? helper,
    Widget? suffix,
  }) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GeminiTheme.inputRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GeminiTheme.inputRadius),
          borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GeminiTheme.inputRadius),
          borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.45), width: 1.4),
        ),
      );

  Widget _pasteSuffix(VoidCallback onPaste) => IconButton(
        tooltip: 'Colar',
        icon: const Icon(Icons.content_paste_rounded, size: 20),
        color: AppColors.primary,
        onPressed: onPaste,
        splashRadius: 22,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      );

  Widget _premiumFieldCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget field,
  }) {
    return Material(
      color: Colors.white,
      elevation: 0,
      shadowColor: AppColors.deepBlueDark.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GeminiTheme.cardRadius),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(GeminiTheme.cardRadius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              AppColors.primary.withValues(alpha: 0.03),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.deepBlueDark.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        iconColor.withValues(alpha: 0.22),
                        iconColor.withValues(alpha: 0.10),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(icon, color: iconColor, size: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            field,
          ],
        ),
      ),
    );
  }

  Widget _scaleCard() => _premiumFieldCard(
        icon: Icons.tag_rounded,
        iconColor: AppColors.primary,
        title: 'Nº Escala',
        subtitle: 'Plantão ou compromisso incluído na escala',
        field: FastTextField(
          controller: _scaleCtrl,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [UpperCaseTextFormatter()],
          scrollPadding: KeyboardFormInsets.fieldScrollPadding(
            context,
            standaloneFullPageForm: true,
          ),
          decoration: _fieldDecoration(
            label: 'Número',
            hint: 'EX.: 123456',
            suffix: _pasteSuffix(
              () => _pasteInto(_scaleCtrl),
            ),
          ),
        ),
      );

  Widget _notesCard() => _premiumFieldCard(
        icon: Icons.notes_rounded,
        iconColor: AppColors.accent,
        title: 'Observações',
        subtitle:
            'Até $kScaleNotesMaxLength caracteres (ideal para observações detalhadas)',
        field: FastTextField(
          controller: _notesCtrl,
          minLines: 4,
          maxLines: 10,
          maxLength: kScaleNotesMaxLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [UpperCaseTextFormatter()],
          scrollPadding: KeyboardFormInsets.fieldScrollPadding(
            context,
            standaloneFullPageForm: true,
          ),
          kind: FastTextFieldKind.prose,
          decoration: _fieldDecoration(
            label: 'Anotações',
            hint: 'DETALHES DO PLANTÃO',
            suffix: _pasteSuffix(
              () => _pasteInto(_notesCtrl, maxLen: kScaleNotesMaxLength),
            ),
          ),
        ),
      );

  void _save() {
    Navigator.pop(
      context,
      ScalePlantaoEditValues(
        scaleNumber: _scaleCtrl.text,
        notes: _notesCtrl.text,
      ),
    );
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
          'Editar nº escala',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2),
        ),
        leading: IconButton(
          tooltip: 'Fechar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
          style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
      ),
      bottomNavigationBar: KeyboardAwareFormBar(
        standaloneFullPageForm: true,
        child: AgendaFormFooterActions(
          onCancel: () => Navigator.of(context).maybePop(),
          onSave: _save,
          saveLabel: 'Salvar',
          saveIcon: Icons.save_rounded,
        ),
      ),
      body: keyboardScaffoldBody(
        standaloneFullPageForm: true,
        SafeArea(
          bottom: false,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFF8FAFC), Color(0xFFE8EDF5)],
              ),
            ),
            child: Builder(
              builder: (ctx) {
                final kb = KeyboardFormInsets.scrollBottomExtra(
                  ctx,
                  standaloneFullPageForm: true,
                );
                return ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + kb),
                  children: [
                    Material(
                      color: Colors.white.withValues(alpha: 0.98),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(
                                  Icons.info_outline_rounded,
                                  color: AppColors.primary,
                                  size: 20,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Número do plantão ou compromisso na escala (com ou sem financeiro). '
                                'Audiências usam Nº Ocorrência e processo (SEI) no módulo Agenda.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.4,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 540;
                        if (wide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _scaleCard()),
                              const SizedBox(width: 14),
                              Expanded(child: _notesCard()),
                            ],
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _scaleCard(),
                            const SizedBox(height: 14),
                            _notesCard(),
                          ],
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
