import 'dart:convert';
import 'package:flutter/material.dart' hide showDatePicker;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../utils/url_launcher_helper.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/user_profile.dart';
import '../services/account_switch_flow.dart';
import '../services/relatorio_service.dart';
import '../utils/pdf_financeiro_super_extrato.dart';
import '../theme/app_colors.dart';
import 'report_preview_screen.dart';
import '../widgets/module_header_premium.dart';
import '../utils/premium_upgrade.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import '../utils/date_picker_a11y.dart';
import '../utils/pwa_install_helper.dart';

class DownloadsScreen extends StatefulWidget {
  final String? uid;
  final UserProfile? profile;
  const DownloadsScreen({super.key, this.uid, this.profile});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day - 30);
  DateTime _to = DateTime.now();

  bool get _isPublic => widget.uid == null || widget.profile == null;

  CollectionReference<Map<String, dynamic>> _txRef(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('transactions');

    CollectionReference<Map<String, dynamic>> get _publicDownloads =>
      FirebaseFirestore.instance.collection('public_downloads');

  static const String _versionJsonUrl = 'https://controletotal-4c867.web.app/version.json';
  static const String _defaultTestFlightPublicLink = 'https://testflight.apple.com/join/pugVHQ6C';
  static const String _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.wisdomapp.app';

  /// No Safari iPhone/iPad e no app iOS nativo: não exibir APK; só TestFlight.
  bool get _hideApkDownloadPlatform {
    if (kIsWeb) return isPwaIos;
    return defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// App Android instalado: não exibir TestFlight / links iOS.
  bool get _hideIosDownloadPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool _isApkAndroidDoc(Map<String, dynamic> data) {
    final icon = (data['icon'] ?? '').toString();
    final title = (data['title'] ?? '').toString().toLowerCase();
    final url = (data['url'] ?? '').toString().toLowerCase();
    if (icon == 'android') return true;
    if (title.contains('apk')) return true;
    if (url.endsWith('.apk')) return true;
    return false;
  }

  bool _isIosDoc(Map<String, dynamic> data) {
    final icon = (data['icon'] ?? '').toString();
    final title = (data['title'] ?? '').toString().toLowerCase();
    final url = (data['url'] ?? '').toString().toLowerCase();
    if (icon == 'ios') return true;
    if (title.contains('testflight') ||
        title.contains('iphone') ||
        title.contains('ios')) {
      return true;
    }
    if (url.contains('testflight.apple.com')) return true;
    return false;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterPublicDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var out = docs;
    if (_hideApkDownloadPlatform) {
      out = out.where((d) => !_isApkAndroidDoc(d.data())).toList();
    }
    if (_hideIosDownloadPlatform) {
      out = out.where((d) => !_isIosDoc(d.data())).toList();
    }
    return out;
  }

  /// Fallback iOS: link TestFlight do version.json (mesmo da landing).
  Future<({String? testFlightUrl, String? version})> _fetchTestFlightFromVersionJson() async {
    try {
      final uri = Uri.parse('$_versionJsonUrl?t=${DateTime.now().millisecondsSinceEpoch}');
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final tf = decoded['testFlightUrl']?.toString().trim();
          final v = decoded['version']?.toString().trim();
          final ok = tf != null && tf.isNotEmpty && (tf.startsWith('http://') || tf.startsWith('https://'));
          return (testFlightUrl: ok ? tf : null, version: v);
        }
      }
    } catch (_) {}
    return (testFlightUrl: null, version: null);
  }

  Widget _buildIosTestFlightFallbackCard() {
    return FutureBuilder<({String? testFlightUrl, String? version})>(
      future: _fetchTestFlightFromVersionJson(),
      builder: (context, snap) {
        final tf = snap.data?.testFlightUrl;
        final version = snap.data?.version;
        final url = (tf != null && tf.isNotEmpty) ? tf : _defaultTestFlightPublicLink;
        if (snap.connectionState == ConnectionState.waiting) {
          return const Card(
            child: ListTile(
              leading: SizedBox(width: 24, height: 24, child: CircularProgressIndicator()),
              title: Text('Carregando...'),
            ),
          );
        }
        return Card(
          child: ListTile(
            leading: const Icon(Icons.download, color: Colors.blueGrey),
            title: Text('WISDOMAPP (TestFlight)${version != null && version.isNotEmpty ? ' (v$version)' : ''}'),
            subtitle: const Text('Toque para instalar no iPhone (beta)'),
            trailing: IconButton(
              icon: const Icon(Icons.open_in_new),
              onPressed: () async {
                try {
                  await openUrlPreferChrome(url);
                } catch (_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Não foi possível abrir o link.')),
                    );
                  }
                }
              },
            ),
          ),
        );
      },
    );
  }

  /// Fallback: quando public_downloads está vazio, busca link da loja no version.json (atualizado no deploy).
  Future<({String? apkUrl, String? version})> _fetchApkFromVersionJson() async {
    try {
      final uri = Uri.parse('$_versionJsonUrl?t=${DateTime.now().millisecondsSinceEpoch}');
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final raw = decoded['apkDownloadUrl']?.toString().trim();
          final v = decoded['version']?.toString().trim();
          if (raw != null &&
              raw.isNotEmpty &&
              (raw.startsWith('http://') || raw.startsWith('https://'))) {
            final lower = raw.toLowerCase();
            final url = (lower.endsWith('.apk') || lower.contains('/apk/')) ? _playStoreUrl : raw;
            return (apkUrl: url, version: v);
          }
        }
      }
    } catch (_) {}
    return (apkUrl: _playStoreUrl, version: null);
  }

  Widget _buildApkFallbackCard() {
    return FutureBuilder<({String? apkUrl, String? version})>(
      future: _fetchApkFromVersionJson(),
      builder: (context, snap) {
        final apkUrl = snap.data?.apkUrl;
        final version = snap.data?.version;
        if (snap.connectionState == ConnectionState.waiting) {
          return const Card(child: ListTile(leading: SizedBox(width: 24, height: 24, child: CircularProgressIndicator()), title: Text('Carregando...')));
        }
        if (apkUrl != null && apkUrl.isNotEmpty) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.shop_rounded, color: Colors.green),
              title: Text('WISDOMAPP — Google Play${version != null && version.isNotEmpty ? ' (v$version)' : ''}'),
              subtitle: const Text('Abrir na loja para instalar ou atualizar'),
              trailing: IconButton(
                icon: const Icon(Icons.open_in_new),
                onPressed: () async {
                  try {
                    await openUrlPreferChrome(apkUrl);
                  } catch (_) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível abrir o link.')));
                  }
                },
              ),
            ),
          );
        }
        return const Card(
          child: ListTile(
            leading: Icon(Icons.download),
            title: Text('Sem downloads publicados'),
            subtitle: Text('Os links aparecerão aqui quando forem liberados.'),
          ),
        );
      },
    );
  }

  Widget _buildPublicDownloadColumn(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final filtered = _filterPublicDocs(docs);
    if (docs.isEmpty) {
      return _hideApkDownloadPlatform ? _buildIosTestFlightFallbackCard() : _buildApkFallbackCard();
    }
    if (filtered.isEmpty) {
      return _hideApkDownloadPlatform ? _buildIosTestFlightFallbackCard() : _buildApkFallbackCard();
    }
    return Column(
      children: filtered.map((doc) {
        final data = doc.data();
        final title = (data['title'] ?? 'Download').toString();
        final subtitle = (data['subtitle'] ?? '').toString();
        final url = (data['url'] ?? '').toString();
        final icon = (data['icon'] ?? '').toString();
        IconData iconData = Icons.download;
        if (icon == 'android') iconData = Icons.android;
        if (icon == 'ios') iconData = Icons.apple;
        if (icon == 'web') iconData = Icons.language;

        return Card(
          child: ListTile(
            leading: Icon(iconData),
            title: Text(title),
            subtitle: Text(subtitle.isEmpty ? 'Link disponível' : subtitle),
            trailing: url.isEmpty
                ? const Icon(Icons.link_off)
                : IconButton(
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () async {
                      if (url.isEmpty) return;
                      try {
                        await openUrlPreferChrome(url);
                      } catch (_) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Não foi possível abrir o link.')),
                          );
                        }
                      }
                    },
                  ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _from = picked);
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _to = picked);
  }

  String _csvHeader() => 'data,tipo,categoria,descricao,valor,status\n';

  String _csvLine(Map<String, dynamic> d) {
    final date = (d['date'] as Timestamp?)?.toDate();
    final dateStr = date == null ? '' : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final type = (d['type'] ?? '').toString();
    final category = (d['category'] ?? '').toString().replaceAll(',', ' ');
    final desc = (d['description'] ?? '').toString().replaceAll(',', ' ');
    final amount = (d['amount'] ?? 0).toString();
    final status = (d['status'] ?? '').toString();
    return '$dateStr,$type,$category,$desc,$amount,$status\n';
  }

  /// Gera PDF do relatório financeiro do período (_from até _to) e abre pré-visualização.
  Future<void> _gerarRelatorioPdf(BuildContext context, String uid) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final snap = await _txRef(uid)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(_from))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(_to))
          .orderBy('date', descending: false)
          .get();

      double totalReceitas = 0;
      double totalDespesas = 0;
      final transacoes = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        final type = (d['type'] ?? 'expense').toString();
        final amount = (d['amount'] ?? 0).toDouble();
        final cat = (d['category'] ?? '').toString().trim();
        final desc = (d['description'] ?? '').toString().trim();
        final dataStr = d['date'] is Timestamp
            ? DateFormat('dd/MM/yyyy').format((d['date'] as Timestamp).toDate())
            : '';
        final sortMs = d['date'] is Timestamp ? (d['date'] as Timestamp).toDate().millisecondsSinceEpoch : 0;
        final isIncome = type == 'income';
        final valorLinha = isIncome ? amount : amount.abs();
        final tituloLinha =
            desc.isNotEmpty ? desc : (cat.isNotEmpty ? cat : (isIncome ? 'Receita' : 'Despesa'));
        if (isIncome) {
          totalReceitas += valorLinha;
        } else {
          totalDespesas += valorLinha;
        }
        transacoes.add({
          'sortMs': sortMs,
          'data': dataStr,
          'categoria': cat,
          'titulo': tituloLinha,
          'descricao': RelatorioService.sanitizeForReport(
            () {
              final raw = (cat.isNotEmpty ? 'Categoria: $cat' : '') +
                  (cat.isNotEmpty && desc.isNotEmpty ? ' — ' : '') +
                  (desc.isNotEmpty ? 'Descrição: $desc' : '');
              return raw.trim().isEmpty ? (isIncome ? 'Receita' : 'Despesa') : raw;
            }(),
          ),
          'tipo': isIncome ? 'receita' : 'despesa',
          'valor': valorLinha,
        });
      }
      transacoes.sort((a, b) => (a['sortMs'] as int).compareTo(b['sortMs'] as int));

      final mes = _from.month == _to.month && _from.year == _to.year
          ? '${DateFormat('MMMM', 'pt_BR').format(_from)}/${_from.year}'
          : 'De ${DateFormat('dd/MM/yyyy').format(_from)} a ${DateFormat('dd/MM/yyyy').format(_to)}';

      if (!context.mounted) return;
      Navigator.of(context).pop();

      final filenameBase = RelatorioService.reportFilenameFromPeriod('despesa_receita', _from, _to);
      final logo = await RelatorioService.loadPdfLogoBytesOnce();
      final nome = (widget.profile?.name ?? '').trim();
      final bytes = await gerarPdfFinanceiroSuperExtrato(
        transacoes: transacoes,
        nomeUsuario: nome.isEmpty ? '—' : nome,
        conta: 'Todas as contas',
        periodo: mes,
        saldoAbertura: 0,
        totalReceitas: totalReceitas,
        totalDespesas: totalDespesas,
        logoPngBytes: logo,
      );
      if (!context.mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ReportPreviewScreen(bytes: bytes, filename: filenameBase),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao gerar PDF: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isPublic) {
      return Scaffold(
        appBar: AppBar(
          leading: Navigator.of(context).canPop()
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Voltar',
                )
              : null,
          title: const Text('Downloads'),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
            const ModuleHeaderPremium(title: 'Downloads Premium', icon: Icons.download_rounded, subtitle: 'Instaladores e acesso web.'),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _publicDownloads.orderBy('order', descending: false).snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                return _buildPublicDownloadColumn(snap.data!.docs);
              },
            ),
          ],
        ),
        ),
      );
    }

    final profile = widget.profile!;
    final uid = widget.uid!;

    if (kIsWeb && !profile.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Downloads')),
        body: SafeArea(
          top: false,
          child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Acesso web liberado apenas para a equipe administrativa.'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () =>
                      AccountSwitchFlow.confirmAndOpenLogin(context),
                  child: const Text('Sair'),
                ),
              ],
            ),
          ),
        ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Voltar',
              )
            : null,
        title: const Text('Downloads'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
          const ModuleHeaderPremium(title: 'Downloads Premium', icon: Icons.download_rounded, subtitle: 'Relatórios, comprovantes e arquivos do app.'),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _publicDownloads.orderBy('order', descending: false).snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              return _buildPublicDownloadColumn(snap.data!.docs);
            },
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(Icons.picture_as_pdf, color: profile.hasActiveLicense ? AppColors.deepBlueDark : Colors.grey),
              title: const Text('Relatório financeiro (PDF)', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Gere PDF do período para contador ou arquivo pessoal. Layout Clean Premium.'),
              trailing: IconButton(
                icon: Icon(Icons.description, color: profile.hasActiveLicense ? AppColors.deepBlueDark : Colors.grey),
                onPressed: profile.hasActiveLicense
                    ? () => _gerarRelatorioPdf(context, uid)
                    : () => mostrarAvisoSeLicencaInativa(context, profile),
                tooltip: 'Gerar PDF',
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('Comprovantes'),
              subtitle: Text('Período: ${_from.day.toString().padLeft(2, '0')}/${_from.month.toString().padLeft(2, '0')}/${_from.year} até ${_to.day.toString().padLeft(2, '0')}/${_to.month.toString().padLeft(2, '0')}/${_to.year}'),
              trailing: IconButton(icon: const Icon(Icons.filter_alt), onPressed: _pickFrom),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(Icons.download_for_offline, color: profile.hasActiveLicense ? null : Colors.grey),
              title: const Text('Exportar lançamentos (CSV)'),
              subtitle: const Text('Gera CSV do período para copiar/usar em planilha.'),
              trailing: IconButton(
                icon: Icon(Icons.file_download, color: profile.hasActiveLicense ? null : Colors.grey),
                onPressed: profile.hasActiveLicense ? () async {
                  final snap = await _txRef(uid)
                      .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(_from))
                      .where('date', isLessThanOrEqualTo: Timestamp.fromDate(_to))
                      .orderBy('date', descending: true)
                      .get();
                  final buffer = StringBuffer();
                  buffer.write(_csvHeader());
                  for (final doc in snap.docs) {
                    buffer.write(_csvLine(doc.data()));
                  }
                  if (!context.mounted) return;
                  final csv = buffer.toString();
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('CSV (copiar)'),
                      content: SingleChildScrollView(child: Text(csv)),
                      actions: [
                        TextButton(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: csv));
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('CSV copiado para a área de transferência.')),
                              );
                            }
                          },
                          child: const Text('Copiar'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Fechar'),
                        ),
                      ],
                    ),
                  );
                } : () => mostrarAvisoSeLicencaInativa(context, profile),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(child: OutlinedButton.icon(onPressed: _pickFrom, icon: const Icon(Icons.date_range), label: const Text('De'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: _pickTo, icon: const Icon(Icons.event), label: const Text('Até'))),
            ],
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _txRef(uid)
                .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(_from))
                .where('date', isLessThanOrEqualTo: Timestamp.fromDate(_to))
                .orderBy('date', descending: true)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs.where((d) => d.data().containsKey('receipt')).toList();
              if (docs.isEmpty) return const Center(child: Text('Nenhum comprovante no período.'));

              return Column(
                children: docs.map((doc) {
                  final data = doc.data();
                  final receipt = Map<String, dynamic>.from(data['receipt'] ?? {});
                  final name = (receipt['name'] ?? receipt['originalName'] ?? 'Comprovante').toString();
                  final link = (receipt['downloadUrl'] ?? receipt['webViewLink'] ?? receipt['webContentLink'] ?? '').toString();
                  final date = (data['date'] as Timestamp?)?.toDate();

                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.cloud_download),
                      title: Text(name),
                      subtitle: Text(date == null ? '' : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}'),
                      trailing: link.isEmpty
                          ? const Icon(Icons.link_off)
                          : IconButton(
                              icon: const Icon(Icons.open_in_new),
                              onPressed: () async {
                                if (link.isEmpty) return;
                                try {
                                  await openUrlPreferChrome(link);
                                } catch (_) {
                                  if (context.mounted) {
                                    showDialog(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: const Text('Link do comprovante'),
                                        content: Text(link),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context),
                                            child: const Text('Fechar'),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
      ),
    );
  }
}
