import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../theme/app_colors.dart';
import '../services/user_restore_service.dart';
import '../utils/date_utils_cordex.dart';

/// Tela para restaurar dados a partir de um arquivo de backup (busca manual no dispositivo ou nuvem).
class RestoreDataScreen extends StatefulWidget {
  final String uid;

  const RestoreDataScreen({super.key, required this.uid});

  @override
  State<RestoreDataScreen> createState() => _RestoreDataScreenState();
}

class _RestoreDataScreenState extends State<RestoreDataScreen> {
  final UserRestoreService _restoreService = UserRestoreService();
  BackupPreview? _preview;
  String? _jsonString;
  String? _pickedFileName;
  bool _loading = false;
  String? _error;

  Future<void> _pickFile() async {
    setState(() {
      _preview = null;
      _jsonString = null;
      _pickedFileName = null;
      _error = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
        dialogTitle: 'Escolha o arquivo de backup',
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      final name = file.name;

      if (bytes == null || bytes.isEmpty) {
        if (kIsWeb) {
          // Web às vezes não retorna bytes; tenta path (alguns plugins leem por path)
          setState(() => _error = 'Não foi possível ler o arquivo. Tente novamente ou use outro navegador.');
        } else {
          setState(() => _error = 'Arquivo vazio ou não acessível.');
        }
        return;
      }

      final jsonString = utf8.decode(bytes);
      final preview = _restoreService.previewFromJsonString(jsonString);

      if (preview == null || !preview.isValid) {
        setState(() => _error = 'Arquivo inválido. Escolha um backup exportado pelo WISDOMAPP (arquivo .json).');
        return;
      }

      setState(() {
        _preview = preview;
        _jsonString = jsonString;
        _pickedFileName = name;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Erro ao abrir arquivo: ${e.toString().split('\n').first}');
    }
  }

  Future<void> _confirmAndRestore() async {
    if (_jsonString == null || _preview == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar restauração'),
        content: const Text(
          'Os dados do backup serão restaurados na sua conta. '
          'Documentos existentes nas mesmas coleções podem ser atualizados. '
          'Deseja continuar?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restaurar')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    try {
      await _restoreService.restore(widget.uid, _jsonString!);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dados restaurados com sucesso.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Erro ao restaurar: ${e.toString().split('\n').first}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Restaurar Dados'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: Colors.blue.shade700, size: 24),
                        const SizedBox(width: 10),
                        Text(
                          'Onde está seu backup?',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.blue.shade900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'O backup pode estar na pasta Downloads, no Google Drive, em outro app de nuvem ou em qualquer pasta do seu aparelho. '
                      'Toque em "Buscar arquivo" e escolha o arquivo .json que você exportou (ex.: controle-total-backup-2025-02-18.json).',
                      style: TextStyle(fontSize: 13, height: 1.5, color: Colors.blue.shade800),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _pickFile,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Buscar arquivo no dispositivo ou nuvem'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded, color: AppColors.error, size: 22),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_error!, style: TextStyle(color: AppColors.error, fontSize: 13))),
                  ],
                ),
              ),
            ],
            if (_preview != null && _jsonString != null) ...[
              const SizedBox(height: 24),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Arquivo selecionado', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                      const SizedBox(height: 4),
                      Text(_pickedFileName ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text('Backup de: $_previewExportDate', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      const SizedBox(height: 16),
                      Text('Dados a restaurar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                      const SizedBox(height: 8),
                      ..._preview!.collectionCounts.entries.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_collectionLabel(e.key), style: const TextStyle(fontSize: 13)),
                            Text('${e.value} itens', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                          ],
                        ),
                      )),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _loading ? null : _confirmAndRestore,
                          icon: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.restore_rounded),
                          label: Text(_loading ? 'Restaurando...' : 'Restaurar dados'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
        ),
      ),
    );
  }

  String get _previewExportDate {
    if (_preview == null || _preview!.exportedAt.isEmpty) return '—';
    try {
      final dt = DateUtilsCordex.parseDateSafe(_preview!.exportedAt);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return _preview!.exportedAt;
    }
  }

  String _collectionLabel(String key) {
    const labels = {
      'settings': 'Configurações',
      'locations': 'Locais (legado)',
      'reminders': 'Lembretes da agenda',
      'transactions': 'Transações financeiras',
      'scales': 'Agenda (legado)',
      'budgets': 'Orçamentos',
      'quotes': 'Cotações',
      'goals': 'Metas (legado)',
      'payments': 'Pagamentos',
      'category_types': 'Categorias',
      'ocorrencias': 'Registros (legado)',
    };
    return labels[key] ?? key;
  }
}
