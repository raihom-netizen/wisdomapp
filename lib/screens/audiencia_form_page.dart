import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide showDatePicker;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../constants/color_palette.dart';
import '../constants/field_text_limits.dart';
import '../models/user_profile.dart';
import '../services/agenda_scale_mirror_service.dart';
import '../theme/gemini_theme.dart';
import '../utils/keyboard_form_scaffold.dart';
import '../utils/premium_upgrade.dart';
import '../widgets/agenda_form_footer_actions.dart';
import '../widgets/agenda_form_validation_alert.dart';
import '../widgets/fast_text_field.dart';
import '../widgets/multi_date_month_picker_dialog.dart';

/// Resultado ao salvar audiência (novo ou edição).
class AudienciaFormResult {
  AudienciaFormResult({
    required this.numeroSei,
    required this.numeroOcorrencia,
    required this.resumoRelato,
    required this.date,
    required this.time,
    required this.endTime,
    required this.colorHex,
    this.localAudiencia = '',
    this.linkSalaAudiencia = '',
    this.oficioBytes,
    this.oficioFileName,
    this.oficioMime,
    this.oficioExtension,
    this.removeOficio = false,
  });

  final String numeroSei;
  final String numeroOcorrencia;
  final String resumoRelato;
  final String localAudiencia;
  final String linkSalaAudiencia;
  final DateTime date;
  final TimeOfDay time;
  final TimeOfDay endTime;
  final String colorHex;
  final Uint8List? oficioBytes;
  final String? oficioFileName;
  final String? oficioMime;
  final String? oficioExtension;
  final bool removeOficio;
}

/// Cadastro / edição de audiência em tela cheia.
class AudienciaFormPage extends StatefulWidget {
  const AudienciaFormPage({
    super.key,
    required this.profile,
    required this.hasActiveLicense,
    this.existingDoc,
    this.initialDate,
  });

  final UserProfile profile;
  final bool hasActiveLicense;
  final QueryDocumentSnapshot<Map<String, dynamic>>? existingDoc;
  final DateTime? initialDate;

  bool get isEdit => existingDoc != null;

  @override
  State<AudienciaFormPage> createState() => _AudienciaFormPageState();
}

class _AudienciaFormPageState extends State<AudienciaFormPage> {
  late TextEditingController _seiCtrl;
  late TextEditingController _ocoCtrl;
  late TextEditingController _relatoCtrl;
  late TextEditingController _localCtrl;
  late TextEditingController _linkCtrl;
  late DateTime _date;
  late TimeOfDay _time;
  late TimeOfDay _endTime;
  late String _colorHex;

  String _existingOficioName = '';
  Uint8List? _pickedOficioBytes;
  String? _pickedOficioName;
  String? _pickedOficioMime;
  String? _pickedOficioExt;
  bool _removeOficio = false;
  bool _pickingFile = false;

  static TimeOfDay _addOneHour(TimeOfDay t) {
    final m = t.hour * 60 + t.minute + 60;
    return TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60);
  }

  static int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  static TimeOfDay _parseHHmm(String s, TimeOfDay fallback) {
    final parts = s.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '');
    final m = int.tryParse(parts.length > 1 ? parts[1] : '');
    if (h == null) return fallback;
    return TimeOfDay(hour: h, minute: m ?? 0);
  }

  @override
  void initState() {
    super.initState();
    final doc = widget.existingDoc;
    if (doc != null) {
      final data = doc.data();
      _seiCtrl = TextEditingController(text: (data['numeroSei'] ?? '').toString());
      _ocoCtrl =
          TextEditingController(text: (data['numeroOcorrencia'] ?? '').toString());
      _relatoCtrl =
          TextEditingController(text: (data['resumoRelato'] ?? '').toString());
      _localCtrl =
          TextEditingController(text: (data['localAudiencia'] ?? '').toString());
      _linkCtrl = TextEditingController(
          text: (data['linkSalaAudiencia'] ?? '').toString());
      _date = (data['date'] as Timestamp?)?.toDate() ??
          DateTime.now().add(const Duration(days: 1));
      _time = _parseHHmm((data['time'] ?? '09:00').toString(),
          const TimeOfDay(hour: 9, minute: 0));
      _endTime = _parseHHmm((data['endTime'] ?? '').toString(), _addOneHour(_time));
      final cor = (data['colorHex'] ?? '').toString().trim();
      _colorHex =
          cor.isNotEmpty ? _normalizeHex(cor) : kAgendaAudienciaDefaultColor;
      _existingOficioName = (data['oficioFileName'] ?? '').toString().trim();
    } else {
      final day = widget.initialDate ?? DateTime.now().add(const Duration(days: 1));
      _seiCtrl = TextEditingController();
      _ocoCtrl = TextEditingController();
      _relatoCtrl = TextEditingController();
      _localCtrl = TextEditingController();
      _linkCtrl = TextEditingController();
      _date = DateTime(day.year, day.month, day.day);
      _time = const TimeOfDay(hour: 9, minute: 0);
      _endTime = const TimeOfDay(hour: 10, minute: 0);
      _colorHex = kAgendaAudienciaDefaultColor;
    }
  }

  @override
  void dispose() {
    _seiCtrl.dispose();
    _ocoCtrl.dispose();
    _relatoCtrl.dispose();
    _localCtrl.dispose();
    _linkCtrl.dispose();
    super.dispose();
  }

  String _normalizeHex(String raw) {
    var h = raw.trim();
    if (h.isEmpty) return kAgendaAudienciaDefaultColor;
    if (!h.startsWith('#')) h = '#$h';
    return h;
  }

  Color _colorFromHex(String hex) {
    final h = hex.replaceFirst('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  InputDecoration _inputDecoration(String label, String hint) => InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GeminiTheme.inputRadius),
          borderSide: BorderSide.none,
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    int? maxLength,
  }) {
    final isMultiline = maxLines != 1;
    return FastTextField(
      controller: controller,
      decoration: _inputDecoration(label, hint),
      kind: isMultiline ? FastTextFieldKind.prose : FastTextFieldKind.standard,
      maxLines: maxLines,
      minLines: isMultiline ? 3 : null,
      maxLength: maxLength,
      scrollPadding: KeyboardFormInsets.fieldScrollPadding(
        context,
        standaloneFullPageForm: true,
      ),
      textInputAction:
          isMultiline ? TextInputAction.newline : TextInputAction.next,
      onSubmitted:
          isMultiline ? null : (_) => FocusScope.of(context).nextFocus(),
    );
  }

  Widget _compactPickerTile({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(GeminiTheme.inputRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GeminiTheme.inputRadius),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          child: Row(
            children: [
              Icon(icon, size: 17, color: const Color(0xFF1A237E)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade700,
                          letterSpacing: 0.2,
                        )),
                    const SizedBox(height: 2),
                    Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          height: 1.1,
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await pickSingleDateWithHolidayCalendar(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _time = picked;
      if (_toMinutes(_endTime) <= _toMinutes(_time)) {
        _endTime = _addOneHour(_time);
      }
    });
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => _endTime = picked);
  }

  Future<void> _abrirSeletorCor() async {
    final palette = kColorPaletteHex.take(72).toList();
    final idx = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (_, scroll) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Cor no calendário',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 10),
              Expanded(
                child: GridView.builder(
                  controller: scroll,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: palette.length,
                  itemBuilder: (_, i) {
                    final c = palette[i];
                    final selected = _normalizeHex(c) == _colorHex;
                    return InkWell(
                      onTap: () => Navigator.pop(ctx, i),
                      borderRadius: BorderRadius.circular(10),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _colorFromHex(c),
                          borderRadius: BorderRadius.circular(10),
                          border: selected
                              ? Border.all(color: Colors.white, width: 3)
                              : null,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (idx == null || !mounted) return;
    if (idx >= 0 && idx < palette.length) {
      setState(() => _colorHex = _normalizeHex(palette[idx]));
    }
  }

  Future<void> _pickOficio() async {
    setState(() => _pickingFile = true);
    try {
      final pick = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      );
      if (pick == null || pick.files.isEmpty) return;
      final f = pick.files.first;
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) return;
      final name = f.name.trim().isEmpty ? 'oficio' : f.name.trim();
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'pdf';
      setState(() {
        _pickedOficioBytes = bytes;
        _pickedOficioName = name;
        _pickedOficioMime = _mimeForExt(ext);
        _pickedOficioExt = ext;
        _removeOficio = false;
      });
    } finally {
      if (mounted) setState(() => _pickingFile = false);
    }
  }

  String _mimeForExt(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      default:
        return 'application/pdf';
    }
  }

  String get _oficioLabel {
    if (_pickedOficioName != null) return _pickedOficioName!;
    if (!_removeOficio && _existingOficioName.isNotEmpty) {
      return _existingOficioName;
    }
    return 'Nenhum anexo';
  }

  Future<void> _submit() async {
    if (!widget.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }

    final ok = await validateAudienciaFormOrShowAlert(
      context,
      numeroSei: _seiCtrl.text,
      numeroOcorrencia: _ocoCtrl.text,
      resumoRelato: _relatoCtrl.text,
    );
    if (!ok || !mounted) return;

    Navigator.of(context).pop(
      AudienciaFormResult(
        numeroSei: _seiCtrl.text.trim(),
        numeroOcorrencia: _ocoCtrl.text.trim(),
        resumoRelato: _relatoCtrl.text,
        localAudiencia: _localCtrl.text.trim(),
        linkSalaAudiencia: _linkCtrl.text.trim(),
        date: DateTime(_date.year, _date.month, _date.day),
        time: _time,
        endTime: _endTime,
        colorHex: _colorHex,
        oficioBytes: _pickedOficioBytes,
        oficioFileName: _pickedOficioName,
        oficioMime: _pickedOficioMime,
        oficioExtension: _pickedOficioExt,
        removeOficio: _removeOficio,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isEdit ? 'Editar audiência' : 'Nova audiência';
    final pickedFill = _colorFromHex(_colorHex);
    final onPicked = pickedFill.computeLuminance() > 0.55
        ? const Color(0xFF0F172A)
        : Colors.white;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      resizeToAvoidBottomInset:
          scaffoldKeyboardResizeToAvoidBottomInset(standaloneFullPageForm: true),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1A237E), Color(0xFF283593), Color(0xFFD4AF37)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2)),
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
          onSave: _submit,
          saveLabel: widget.isEdit ? 'Salvar alterações' : 'Salvar audiência',
        ),
      ),
      body: keyboardScaffoldBody(
        standaloneFullPageForm: true,
        SafeArea(
          bottom: false,
          child: Builder(builder: (ctx) {
            final kb = KeyboardFormInsets.scrollBottomExtra(
              ctx,
              extra: 0,
              standaloneFullPageForm: true,
            );
            return ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + kb),
              children: [
                _buildHeader(title),
                const SizedBox(height: 10),
                _field(
                  controller: _seiCtrl,
                  label: 'Número SEI *',
                  hint: 'Ex.: 12345.678901/2024-00',
                ),
                const SizedBox(height: 10),
                _field(
                  controller: _ocoCtrl,
                  label: 'Nº da escala / ocorrência *',
                  hint: 'Número da escala ou ocorrência',
                ),
                const SizedBox(height: 10),
                _field(
                  controller: _relatoCtrl,
                  label: 'Resumo / relato *',
                  hint: 'Assunto ou relato da audiência',
                  maxLines: 5,
                  maxLength: kAudienciaRelatoMaxLength,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: _compactPickerTile(
                        icon: Icons.calendar_today_rounded,
                        label: 'DATA *',
                        value: DateFormat('dd/MM (EEE)', 'pt_BR').format(_date),
                        onTap: _pickDate,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: _compactPickerTile(
                        icon: Icons.schedule_rounded,
                        label: 'INÍCIO *',
                        value: _time.format(context),
                        onTap: _pickStartTime,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: _compactPickerTile(
                        icon: Icons.schedule_rounded,
                        label: 'FIM *',
                        value: _endTime.format(context),
                        onTap: _pickEndTime,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _field(
                  controller: _localCtrl,
                  label: 'Local (opcional)',
                  hint: 'Fórum, sala presencial, endereço…',
                ),
                const SizedBox(height: 10),
                _field(
                  controller: _linkCtrl,
                  label: 'Link da sala (opcional)',
                  hint: 'https://… para audiência virtual',
                ),
                const SizedBox(height: 10),
                _buildColorCard(pickedFill, onPicked),
                const SizedBox(height: 10),
                _buildAnexoCard(),
                const SizedBox(height: 6),
                _buildInfoRodape(),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildHeader(String title) {
    return Material(
      color: Colors.white.withValues(alpha: 0.98),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Padding(
                padding: EdgeInsets.all(7),
                child: Icon(Icons.gavel_rounded,
                    color: Color(0xFF1A237E), size: 20),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                          height: 1.1)),
                  const SizedBox(height: 1),
                  Text(
                    'Campos com * são obrigatórios · link, local e anexo são opcionais',
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.15,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorCard(Color pickedFill, Color onPicked) {
    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            const Icon(Icons.palette_rounded, size: 18, color: Color(0xFF1A237E)),
            const SizedBox(width: 9),
            const Expanded(
              child: Text('Cor no calendário',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A))),
            ),
            Material(
              color: pickedFill,
              borderRadius: BorderRadius.circular(12),
              elevation: 2,
              child: InkWell(
                onTap: _abrirSeletorCor,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.colorize_rounded, color: onPicked, size: 16),
                      const SizedBox(width: 6),
                      Text('Trocar',
                          style: TextStyle(
                              color: onPicked,
                              fontWeight: FontWeight.w900,
                              fontSize: 12.5)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnexoCard() {
    final hasAnexo = _pickedOficioName != null ||
        (!_removeOficio && _existingOficioName.isNotEmpty);

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.attach_file_rounded,
                    size: 18, color: Color(0xFF1A237E)),
                SizedBox(width: 8),
                Text('Anexo / ofício (opcional)',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13.5)),
              ],
            ),
            const SizedBox(height: 8),
            Text(_oficioLabel,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickingFile ? null : _pickOficio,
                    icon: _pickingFile
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file_rounded, size: 18),
                    label: Text(hasAnexo ? 'Trocar anexo' : 'Anexar arquivo'),
                  ),
                ),
                if (hasAnexo) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Remover anexo',
                    onPressed: () => setState(() {
                      _pickedOficioBytes = null;
                      _pickedOficioName = null;
                      _pickedOficioMime = null;
                      _pickedOficioExt = null;
                      _removeOficio = true;
                    }),
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Color(0xFFB91C1C)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRodape() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1A237E).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1A237E).withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.event_note_rounded,
                size: 16, color: Color(0xFF1A237E)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'A audiência aparece no painel, na Agenda e no calendário de Escalas. '
                'Você receberá lembretes conforme as notificações configuradas.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.grey.shade800,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
