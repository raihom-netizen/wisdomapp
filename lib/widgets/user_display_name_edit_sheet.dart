import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/user_display_name_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_context.dart';

/// Sheet moderno — editar nome/sobrenome exibidos no painel (emoji permitido).
Future<bool?> showUserDisplayNameEditSheet(
  BuildContext context, {
  required UserProfile profile,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _UserDisplayNameEditSheet(profile: profile),
  );
}

class _UserDisplayNameEditSheet extends StatefulWidget {
  const _UserDisplayNameEditSheet({required this.profile});

  final UserProfile profile;

  @override
  State<_UserDisplayNameEditSheet> createState() =>
      _UserDisplayNameEditSheetState();
}

class _UserDisplayNameEditSheetState extends State<_UserDisplayNameEditSheet> {
  late final TextEditingController _firstCtrl;
  late final TextEditingController _lastCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final parts = widget.profile.displayNamePartsForEdit;
    _firstCtrl = TextEditingController(text: parts.$1);
    _lastCtrl = TextEditingController(text: parts.$2);
    _firstCtrl.addListener(_onFieldsChanged);
    _lastCtrl.addListener(_onFieldsChanged);
  }

  @override
  void dispose() {
    _firstCtrl.removeListener(_onFieldsChanged);
    _lastCtrl.removeListener(_onFieldsChanged);
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    super.dispose();
  }

  void _onFieldsChanged() {
    if (mounted) setState(() {});
  }

  String get _previewName {
    final full = UserProfile.composeDisplayNameParts(
      _firstCtrl.text,
      _lastCtrl.text,
    );
    return full.isEmpty ? 'Seu nome aqui' : full;
  }

  String get _previewInitial {
    final name = _previewName;
    if (name == 'Seu nome aqui') return '?';
    final first = name.characters.first;
    if (RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]', unicode: true).hasMatch(first)) {
      return first.toUpperCase();
    }
    return first;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await UserDisplayNameService.instance.saveDisplayNameParts(
        uid: widget.profile.uid,
        firstName: _firstCtrl.text,
        lastName: _lastCtrl.text,
        currentProfile: widget.profile,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nome atualizado no painel e no menu.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ArgumentError
                ? e.message?.toString() ?? 'Preencha nome ou sobrenome.'
                : 'Não foi possível salvar. Tente novamente.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.isDarkMode
              ? context.appSurface
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: context.isDarkMode
                          ? context.appChipIdleBorder
                          : Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Text(
                  'Como quer ser chamado?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: context.appTextPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Nome e sobrenome aparecem no painel inicial e no menu. Emoji permitido. Sincroniza em todos os aparelhos.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: context.appTextSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        AppColors.deepBlueDark,
                        AppColors.deepBlue,
                        AppColors.accent
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.deepBlue.withValues(alpha: 0.25),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _previewInitial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Prévia no painel',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.82),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Olá, $_previewName',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1.2,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _nameField(
                  controller: _firstCtrl,
                  label: 'Nome',
                  hint: 'Ex.: Flávio ou 🚓 Flávio',
                ),
                const SizedBox(height: 12),
                _nameField(
                  controller: _lastCtrl,
                  label: 'Sobrenome',
                  hint: 'Ex.: Henrique',
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(_saving ? 'Salvando…' : 'Salvar nome'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _nameField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.words,
      maxLength: UserDisplayNameService.maxPartLength,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        filled: true,
        fillColor: context.isDarkMode ? context.appInputFill : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
              color: context.isDarkMode
                  ? context.appChipIdleBorder
                  : Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
              color: context.isDarkMode
                  ? context.appChipIdleBorder
                  : Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }
}
