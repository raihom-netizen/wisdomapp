import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode, compute;
import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import '../constants/app_verse.dart';
import '../constants/date_time_formats.dart';
import '../constants/color_palette.dart';
import '../constants/default_ocorrencias_naturezas.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../constants/produtividade_module_icons.dart';
import '../services/ocorrencias_service.dart';
import '../services/ocorrencias_naturezas_service.dart';
import '../services/produtividade_config_service.dart';
import '../services/produtividade_scale_mirror_service.dart';
import '../services/relatorio_service.dart';
import '../utils/anexo_viewer_helper.dart';
import '../utils/keyboard_form_scaffold.dart';
import '../utils/home_shell_layout.dart';
import '../utils/premium_upgrade.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/produtividade_ocorrencias_pdf_partition.dart';
import 'report_preview_screen.dart';
import '../widgets/date_time_field.dart';
import '../widgets/produtividade_em_aberto_sheet.dart';

/// Módulo Controle Produtividade/Ocorrências: lançar ocorrências, editar/remover,
/// marcar para folga e gerar PDF de solicitação.
class OcorrenciasScreen extends StatefulWidget {
  final String uid;
  final UserProfile profile;
  final void Function(int index)? onNavigateTo;

  /// Quando dentro do [HomeShell]: scroll volta ao topo ao mudar de módulo.
  final ScrollController? shellScrollController;

  const OcorrenciasScreen({
    super.key,
    required this.uid,
    required this.profile,
    this.onNavigateTo,
    this.shellScrollController,
  });

  @override
  State<OcorrenciasScreen> createState() => _OcorrenciasScreenState();
}

/// Opções do filtro "Status da folga".
enum _StatusFolgaFilter { todas, disponiveis, usadas }

/// Período do painel resumo no topo (Pontos em aberto / Folgas tiradas).
enum _ResumoPeriodo { mesAtual, mesAnterior, anual, personalizado }

class _OcorrenciasScreenState extends State<OcorrenciasScreen> {
  final OcorrenciasService _ocorrenciasService = OcorrenciasService();
  final OcorrenciasNaturezasService _naturezasService = OcorrenciasNaturezasService();
  StreamSubscription<fa.User?>? _authStateSub;
  String? _lastAuthUid;

  /// Blindagem: usa UID efetivo (titular quando sub-login).
  String get _userDocId => firestoreUserDocIdStrictFromSession();

  bool _topoExpandido = true;
  // Filtro padrão ao entrar: "Disponíveis para folga" (ocorrências em aberto).
  // O usuário troca o chip para ver as já tiradas; antes era 'Todas', mas
  // o usuário pediu para abrir focado nas ocorrências ainda em aberto.
  _StatusFolgaFilter _statusFolga = _StatusFolgaFilter.disponiveis;

  // Período do painel-resumo (Pontos em aberto / Folgas tiradas). Padrão: ano civil atual.
  _ResumoPeriodo _resumoPeriodo = _ResumoPeriodo.anual;
  DateTime? _resumoCustomStart;
  DateTime? _resumoCustomEnd;
  // Quando o usuário escolhe **Personalizado…**, em vez de abrir uma nova
  // tela (showDateRangePicker), expandimos um painel inline na mesma tela
  // com os campos "De" e "Até" (padrão idêntico ao módulo Escalas).
  bool _resumoCustomExpanded = false;
  final Set<String> _selecionadosFolga = {};
  /// Vista «Já usadas»: seleção para remover `folgaDate` em lote (remarcar folga).
  final Set<String> _selecionadosLimparFolga = {};
  DateTime? _dataFolgaEscolhida = DateTime.now();
  /// Cor do espelho no calendário de Escalas ao confirmar folga (padrão = plantão Ordinário).
  String _folgaCalendarColorHex = kProdutividadeFolgaCalendarDefaultHex;
  bool _loadingNaturezas = true;
  List<OcorrenciaNatureza> _naturezas = [];
  final Set<String> _legacyDataLoggedIds = <String>{};

  static const double _radius = 16;
  static const double _radiusLg = 20;
  static const int _anexoMaxBytes = 5 * 1024 * 1024;
  static const int _anexoImageTargetBytes = 700 * 1024;
  static const List<String> _anexoAllowedExtensions = ['png', 'jpg', 'jpeg', 'pdf'];

  /// Faixa superior do cabeçalho do módulo (gradiente logo).
  Widget _buildModuleHeroBanner() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_radiusLg),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: AppColors.logoGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -24,
              top: -24,
              child: Icon(
                ProdutividadeModuleIcons.banner,
                size: 120,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      ProdutividadeModuleIcons.nav,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Lançamentos, pontos e solicitação de folga em um só lugar.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.95),
                        height: 1.3,
                      ),
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

  Widget _dialogGradientTitle({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: AppColors.logoGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1.2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _aplicarFiltroFolga(List<Map<String, dynamic>> list) {
    switch (_statusFolga) {
      case _StatusFolgaFilter.todas:
        return list;
      case _StatusFolgaFilter.disponiveis:
        return list.where((e) => e['folgaDate'] == null).toList();
      case _StatusFolgaFilter.usadas:
        return list.where((e) => e['folgaDate'] != null).toList();
    }
  }

  DateTime _toDate(dynamic v) {
    if (v == null) return DateTime(2000, 1, 1);
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime(2000, 1, 1);
  }

  bool _isLegacyDataIncomplete(Map<String, dynamic> m) {
    final hasDate = m['date'] != null || m['createdAt'] != null;
    final label = _naturezaLabelFromDoc(m);
    final hasNatureza =
        label.isNotEmpty && label != 'Ocorrência sem natureza';
    return !hasDate || !hasNatureza;
  }

  /// Lista de ocorrências: agrupada por folga quando "Já usadas"; ordem crescente (menor para maior).
  Widget _buildOcorrenciasList(List<Map<String, dynamic>> filtrada) {
    switch (_statusFolga) {
      case _StatusFolgaFilter.usadas:
        final grouped = <DateTime, List<Map<String, dynamic>>>{};
        for (final e in filtrada) {
          final dt = _toDate(e['folgaDate']);
          grouped.putIfAbsent(DateTime(dt.year, dt.month, dt.day), () => []).add(e);
        }
        final folgaDates = grouped.keys.toList()..sort((a, b) => a.compareTo(b));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: folgaDates.map((folgaDay) {
            final ocorrencias = grouped[folgaDay]!;
            ocorrencias.sort((a, b) => _toDate(a['date']).compareTo(_toDate(b['date'])));
            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCabecalhoGrupoFolga(folgaDay, ocorrencias),
                  ...ocorrencias.map((e) => _tileOcorrencia(e)),
                ],
              ),
            );
          }).toList(),
        );
      case _StatusFolgaFilter.disponiveis:
      case _StatusFolgaFilter.todas:
        final sorted = List<Map<String, dynamic>>.from(filtrada)
          ..sort((a, b) => _toDate(a['date']).compareTo(_toDate(b['date'])));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: sorted.map((e) => _tileOcorrencia(e)).toList(),
        );
    }
  }

  Widget _buildCabecalhoGrupoFolga(DateTime folgaDay, List<Map<String, dynamic>> ocorrencias) {
    final ids = ocorrencias.map((e) => (e['id'] ?? '').toString()).where((s) => s.isNotEmpty).toList();
    final todasSel = ids.isNotEmpty && ids.every(_selecionadosLimparFolga.contains);
    final selParaAcao = ids.where(_selecionadosLimparFolga.contains).toList();
    final podeBulk = widget.profile.hasActiveLicense && ids.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Data da folga: ${DateTimeFormats.dateBR.format(folgaDay)} (${_diaSemanaCompleto(folgaDay)})',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          if (podeBulk) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  label: Text(todasSel ? 'Desmarcar todas deste dia' : 'Selecionar todas neste dia'),
                  avatar: Icon(
                    todasSel ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  selected: todasSel,
                  onSelected: (_) {
                    setState(() {
                      if (todasSel) {
                        for (final id in ids) {
                          _selecionadosLimparFolga.remove(id);
                        }
                      } else {
                        for (final id in ids) {
                          _selecionadosLimparFolga.add(id);
                        }
                      }
                    });
                  },
                ),
                FilledButton.tonalIcon(
                  onPressed: selParaAcao.isNotEmpty
                      ? () => _confirmarELimparFolgaEmIds(selParaAcao)
                      : null,
                  icon: const Icon(Icons.event_busy_rounded, size: 20),
                  label: Text(
                    selParaAcao.isEmpty
                        ? 'Limpar data da folga (selecione os RAI)'
                        : 'Limpar data da folga (${selParaAcao.length})',
                  ),
                  style: FilledButton.styleFrom(
                    foregroundColor: AppColors.deepBlueDark,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Use quando cancelar a folga ou para voltar os pontos a «disponíveis» e marcar folga noutra data.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.25),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmarELimparFolgaEmIds(List<String> ids) async {
    if (ids.isEmpty || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.event_busy_rounded, color: AppColors.accent),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Limpar data da folga?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        content: Text(
          '${ids.length} ocorrência(s) deixam de estar vinculadas a esta data de folga. '
          'Os pontos voltam a contar como disponíveis para marcar outra folga. '
          'O lançamento correspondente no calendário de Escalas será removido.',
          style: const TextStyle(fontSize: 14, height: 1.35, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final datasFolga = await _coletarDatasFolgaDosIds(ids);
      await _ocorrenciasService.limparDatasFolga(_userDocId, ids);
      await _syncCalendarioAposLimparFolga(datasFolga);
      if (!mounted) return;
      setState(() {
        for (final id in ids) {
          _selecionadosLimparFolga.remove(id);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ids.length == 1
                ? 'Data da folga removida. O calendário de Escalas foi atualizado.'
                : 'Datas da folga removidas (${ids.length}). O calendário de Escalas foi atualizado.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível atualizar: ${e.toString().split('\n').first}')),
        );
      }
    }
  }

  /// Limpa o cache local do Firestore e força um novo carregamento.
  /// Útil quando o usuário relata "Não foi possível carregar" e a culpa é
  /// de um cache corrompido após troca de sessão / atualização rápida.
  Future<void> _clearCacheAndRetry() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Limpando cache local…')),
      );
      try {
        await FirebaseFirestore.instance.terminate();
      } catch (_) {}
      try {
        await FirebaseFirestore.instance.clearPersistence();
      } catch (_) {}
      if (!mounted) return;
      setState(() {}); // refaz o StreamBuilder com novo `watch`
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cache limpo. Tentando recarregar…')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível limpar o cache: $e')),
      );
    }
  }

  Future<Set<DateTime>> _coletarDatasFolgaDosIds(List<String> ids) async {
    final out = <DateTime>{};
    if (ids.isEmpty || _userDocId.isEmpty) return out;
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(_userDocId)
        .collection('ocorrencias');
    for (final id in ids) {
      try {
        final snap = await col.doc(id).get();
        final fd = snap.data()?['folgaDate'];
        if (fd is Timestamp) {
          final t = fd.toDate();
          out.add(DateTime(t.year, t.month, t.day));
        }
      } catch (_) {}
    }
    return out;
  }

  Future<void> _syncCalendarioAposLimparFolga(Iterable<DateTime> datas) async {
    if (_userDocId.isEmpty) return;
    for (final d in datas) {
      await ProdutividadeScaleMirrorService.deleteMirrorIfNoOccurrences(
        userDocId: _userDocId,
        folgaDay: d,
      );
    }
  }

  Color _colorFromHex6(String hex) {
    var h = hex.replaceFirst('#', '').trim();
    if (h.length == 8) h = h.substring(2);
    if (h.length != 6) return const Color(0xFF2D5BFF);
    return Color(0xFF000000 | int.parse(h, radix: 16));
  }

  static String _normalizeHexFolga(String hex) {
    var h = hex
        .replaceFirst('#', '')
        .replaceFirst(RegExp(r'^0x', caseSensitive: false), '')
        .trim();
    if (h.length > 6) h = h.substring(h.length - 6);
    if (h.length < 6) return kProdutividadeFolgaCalendarDefaultHex;
    return '#${h.toUpperCase()}';
  }

  /// Igual ao módulo Audiência: amostra da cor + «Trocar» → diálogo com grelha (72 tons + atalhos).
  Future<void> _abrirSeletorCorFolga() async {
    final palette = kColorPaletteHex.take(72).toList();
    final colors = palette.map(_colorFromHex6).toList();
    final picked = await showDialog<String>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(18, 12, 8, 2),
        title: Row(
          children: [
            const Expanded(
              child: Text(
                'Cor no calendário (Escalas)',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            TextButton.icon(
              onPressed: () => Navigator.pop(dlgCtx),
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Fechar'),
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Atalhos (mesmos tons da Agenda)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: Icon(Icons.schedule_rounded,
                        size: 18, color: _colorFromHex6(kCalendarPresetPlantaoOrdinarioHex)),
                    label: const Text('Plantão'),
                    onPressed: () =>
                        Navigator.pop(dlgCtx, kCalendarPresetPlantaoOrdinarioHex),
                  ),
                  ActionChip(
                    avatar: Icon(Icons.gavel_rounded,
                        size: 18, color: _colorFromHex6(kCalendarPresetAudienciaHex)),
                    label: const Text('Audiências'),
                    onPressed: () =>
                        Navigator.pop(dlgCtx, kCalendarPresetAudienciaHex),
                  ),
                  ActionChip(
                    avatar: Icon(Icons.event_rounded,
                        size: 18, color: _colorFromHex6(kCalendarPresetCompromissoHex)),
                    label: const Text('Compromisso'),
                    onPressed: () =>
                        Navigator.pop(dlgCtx, kCalendarPresetCompromissoHex),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Todas as cores',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: List.generate(colors.length, (i) {
                  final c = colors[i];
                  final hexStr = palette[i];
                  return InkWell(
                    onTap: () => Navigator.pop(dlgCtx, hexStr),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: c.withValues(alpha: 0.5),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _folgaCalendarColorHex = _normalizeHexFolga(picked));
  }

  /// Cartão estilo Audiência: padrão visível + botão «Trocar» abre o grid.
  Widget _buildFolgaCalendarColorSection() {
    final pickedFill = _colorFromHex6(_folgaCalendarColorHex);
    final onPicked = pickedFill.computeLuminance() > 0.55
        ? const Color(0xFF0F172A)
        : Colors.white;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.white,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Icon(Icons.palette_rounded,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cor no calendário',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Padrão: plantão Ordinário (azul). Toque em Trocar para escolher outra cor ou atalho.',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                Material(
                  color: pickedFill,
                  borderRadius: BorderRadius.circular(12),
                  elevation: 2,
                  shadowColor: pickedFill.withValues(alpha: 0.45),
                  child: InkWell(
                    onTap: _abrirSeletorCorFolga,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.colorize_rounded,
                              color: onPicked, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            'Trocar',
                            style: TextStyle(
                              color: onPicked,
                              fontWeight: FontWeight.w900,
                              fontSize: 12.5,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => setState(() => _folgaCalendarColorHex =
                kProdutividadeFolgaCalendarDefaultHex),
            child: const Text('Restaurar padrão (plantão)'),
          ),
        ),
      ],
    );
  }

  /// Pré-visualização premium + confirmação antes de gerar PDF, gravar folga e espelho no calendário.
  Future<void> _abrirConfirmacaoFolgaPremium({
    required int pontuacaoParaFolga,
    required int totalPontos,
  }) async {
    if (!mounted) return;
    if (_dataFolgaEscolhida == null || _selecionadosFolga.isEmpty) return;
    if (totalPontos < pontuacaoParaFolga) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Selecione ocorrências que somem pelo menos $pontuacaoParaFolga pts. Total: $totalPontos pts.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    final dataFolga = _dataFolgaEscolhida!;
    final restantes = totalPontos - pontuacaoParaFolga;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: AppKeyboardInsets.of(ctx)),
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.event_available_rounded,
                            color: AppColors.accent, size: 28),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Confirmar folga',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Revise os dados antes de gerar o PDF e registar no sistema.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _linhaResumoFolga(
                              'Ocorrências', '${_selecionadosFolga.length} selecionada(s)'),
                          const SizedBox(height: 8),
                          _linhaResumoFolga(
                              'Pontuação total', '$totalPontos pts'),
                          const SizedBox(height: 8),
                          _linhaResumoFolga('Meta para 1 folga',
                              '$pontuacaoParaFolga pts (Configurações)'),
                          if (restantes > 0) ...[
                            const SizedBox(height: 8),
                            _linhaResumoFolga(
                                'Sobra após folga', '$restantes pts (nova ocorrência)'),
                          ],
                          const SizedBox(height: 8),
                          _linhaResumoFolga(
                            'Data da folga',
                            DateTimeFormats.dateBR.format(dataFolga),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: _colorFromHex6(_folgaCalendarColorHex),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey.shade400, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: _colorFromHex6(_folgaCalendarColorHex)
                                    .withValues(alpha: 0.45),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Cor no calendário de Escalas: igual ao módulo Audiência — Trocar abre o grid; padrão é o azul do plantão Ordinário.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade800,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Será criado um compromisso colorido no calendário de Escalas (módulo Escalas) na data escolhida. '
                      'Use «Trocar» acima para escolher a cor — igual Audiência e Compromissos. '
                      'Para remover, limpe aqui em Produtividade ou limpe o dia no calendário de Escalas.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        unawaited(_gerarPdfSolicitacaoFolga());
                      },
                      icon: const Icon(Icons.check_circle_rounded),
                      label: const Text(
                        'Confirmar e gerar PDF',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _linhaResumoFolga(String titulo, String valor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 132,
          child: Text(
            titulo,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            valor,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _lastAuthUid = fa.FirebaseAuth.instance.currentUser?.uid;
    _authStateSub = fa.FirebaseAuth.instance.authStateChanges().listen((u) {
      if (!mounted) return;
      final id = u?.uid;
      if (id == _lastAuthUid) return;
      _lastAuthUid = id;
      setState(() {});
      unawaited(_carregarNaturezas());
    });
    _carregarNaturezas();
  }

  @override
  void dispose() {
    _authStateSub?.cancel();
    super.dispose();
  }

  Future<void> _carregarNaturezas() async {
    final uid = _userDocId;
    if (uid.isEmpty) {
      if (mounted) {
        setState(() {
          _naturezas = [];
          _loadingNaturezas = true;
        });
      }
      return;
    }
    try {
      final list = await _naturezasService.load(uid);
      if (mounted) {
        setState(() {
          _naturezas = list;
          _loadingNaturezas = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _naturezas = [];
          _loadingNaturezas = false;
        });
      }
    }
  }

  String _formatDate(dynamic v) {
    if (v == null) return '';
    if (v is Timestamp) return DateTimeFormats.dateBR.format(v.toDate());
    if (v is DateTime) return DateTimeFormats.dateBR.format(v);
    return v.toString();
  }

  /// Data de ocorrência com fallbacks (legado / tipos heterogéneos — evita linhas “vazias” na grid).
  String _formatDateAny(dynamic v) {
    if (v == null) return '';
    if (v is Timestamp) return DateTimeFormats.dateBR.format(v.toDate());
    if (v is DateTime) return DateTimeFormats.dateBR.format(v);
    if (v is int) {
      if (v > 2000000000000) return DateTimeFormats.dateBR.format(DateTime.fromMillisecondsSinceEpoch(v));
      if (v > 2000000000) return DateTimeFormats.dateBR.format(DateTime.fromMillisecondsSinceEpoch(v * 1000));
    }
    if (v is String) {
      final t = DateTime.tryParse(v.trim());
      if (t != null) return DateTimeFormats.dateBR.format(t);
    }
    final s = v.toString().trim();
    if (s.isEmpty || s == 'null' || s == 'Instance of \'FieldValue\'') return '';
    return s;
  }

  /// Rótulo de natureza com fallbacks (map legado, campos alternativos).
  String _naturezaLabelFromDoc(Map<String, dynamic> e) {
    dynamic raw = e['naturezaLabel'];
    if (raw == null || raw.toString().trim().isEmpty) raw = e['natureza'];
    if (raw == null || raw.toString().trim().isEmpty) raw = e['descricao'];
    if (raw == null || raw.toString().trim().isEmpty) raw = e['titulo'];
    if (raw == null || raw.toString().trim().isEmpty) raw = e['nome'];
    if (raw is Map) {
      try {
        final m = Map<String, dynamic>.from(raw);
        final nested = (m['label'] ?? m['nome'] ?? m['titulo'] ?? m['descricao'] ?? '')
            .toString()
            .trim();
        if (nested.isNotEmpty) return nested;
      } catch (_) {}
    }
    final out = (raw ?? '').toString().trim();
    if (out.isEmpty || out == '{}' || out == 'null') return 'Ocorrência sem natureza';
    return out;
  }

  static final List<String> _diasSemana = [
    'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado', 'Domingo',
  ];
  String _diaSemana(DateTime d) => _diasSemana[d.weekday - 1];
  String _diaSemanaCompleto(DateTime d) {
    final w = d.weekday;
    if (w >= 1 && w <= 5) return '${_diasSemana[w - 1].toLowerCase()}-feira';
    return _diasSemana[w - 1].toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 720;
    final embeddedInShell = widget.shellScrollController != null;
    final id = _userDocId;
    return Scaffold(
      resizeToAvoidBottomInset: scaffoldKeyboardResizeToAvoidBottomInset(
        embeddedInHomeShell: embeddedInShell,
      ),
      backgroundColor: const Color(0xFFEEF2F7),
      body: SafeArea(
        bottom: homeShellSafeAreaBottom(embeddedInHomeShell: embeddedInShell),
        child: CustomScrollView(
        controller: widget.shellScrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, isNarrow ? 4 : 2, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildModuleHeroBanner(),
                  const SizedBox(height: 12),
                  _buildResumoProdutividade(),
                  const SizedBox(height: 12),
                  _buildAcoesRapidasPremium(),
                  const SizedBox(height: 16),
                  _buildTopoRecolher(),
                  const SizedBox(height: 16),
                  if (id.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('A sincronizar sessão…', textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    )
                  else
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    key: ValueKey<String>('ocorrencias-$id'),
                    stream: _ocorrenciasService.watch(id),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.error_outline_rounded,
                                      size: 48,
                                      color: Colors.orange.shade700),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Não foi possível carregar as ocorrências. Verifique a sessão e a rede.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.grey.shade800,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 12),
                                  // Detalhe técnico (sempre visível, ajuda
                                  // o suporte mesmo em produção).
                                  Theme(
                                    data: Theme.of(context).copyWith(
                                      dividerColor: Colors.transparent,
                                    ),
                                    child: ExpansionTile(
                                      tilePadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 8),
                                      childrenPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4),
                                      title: const Text(
                                        'Mostrar detalhe técnico (para o suporte)',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      children: [
                                        SelectableText(
                                          snap.error?.toString() ??
                                              'erro desconhecido',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade700,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    alignment: WrapAlignment.center,
                                    children: [
                                      FilledButton.icon(
                                        onPressed: () => setState(() {}),
                                        icon: const Icon(
                                            Icons.refresh_rounded),
                                        label:
                                            const Text('Tentar novamente'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: _clearCacheAndRetry,
                                        icon: const Icon(
                                            Icons.cleaning_services_rounded),
                                        label: const Text(
                                            'Limpar cache local e tentar'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                      if (!snap.hasData) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      final docs = snap.data!.docs;
                      final list = docs.map((d) {
                        final m = Map<String, dynamic>.from(d.data());
                        m['id'] = d.id;
                        if (_isLegacyDataIncomplete(m)) {
                          m['_legacyIncomplete'] = true;
                          if (kDebugMode && !_legacyDataLoggedIds.contains(d.id)) {
                            _legacyDataLoggedIds.add(d.id);
                            debugPrint(
                              '[Produtividade][registro-legado] id=${d.id} date=${m['date']} createdAt=${m['createdAt']} naturezaLabel=${m['naturezaLabel']}',
                            );
                          }
                        }
                        return m;
                      }).toList();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildCardFolga(list),
                          const SizedBox(height: 20),
                          _sectionTitle('Ocorrências'),
                          const SizedBox(height: 12),
                          if (list.isEmpty)
                            _emptyCard('Nenhuma ocorrência lançada. Toque em + para adicionar.')
                          else ...[
                            Builder(
                              builder: (context) {
                                final filtrada = _aplicarFiltroFolga(list);
                                if (filtrada.isEmpty) {
                                  return _emptyCard(
                                    _statusFolga == _StatusFolgaFilter.todas
                                        ? 'Nenhuma ocorrência lançada. Toque em + para adicionar.'
                                        : 'Nenhuma ocorrência com esse status. Tente outro filtro.',
                                  );
                                }
                                return _buildOcorrenciasList(filtrada);
                              },
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  if (!embeddedInShell && AppVerse.short.isNotEmpty)
                    Text(
                      AppVerse.short,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  SizedBox(
                    height: homeShellFabScrollTail(
                      context,
                      embeddedInHomeShell: embeddedInShell,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
      floatingActionButton: widget.profile.hasActiveLicense
          ? FloatingActionButton.extended(
              onPressed: () => _abrirFormNovaOcorrencia(context),
              elevation: 4,
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.post_add_rounded, color: Colors.white),
              label: const Text(
                'Nova ocorrência',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildTopoRecolher() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_radiusLg),
        border: Border.all(
          color: AppColors.deepBlueDark.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlueDark.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(_radiusLg),
        child: InkWell(
          onTap: () => setState(() => _topoExpandido = !_topoExpandido),
          borderRadius: BorderRadius.circular(_radiusLg),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _topoExpandido ? Icons.keyboard_double_arrow_up_rounded : Icons.keyboard_double_arrow_down_rounded,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _topoExpandido ? 'Recolher' : 'Expandir filtros',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
                if (_topoExpandido) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.filter_alt_rounded, size: 22, color: AppColors.primary.withValues(alpha: 0.85)),
                      const SizedBox(width: 8),
                      Text(
                        'Status da folga',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chipFolga(_StatusFolgaFilter.todas, 'Todas', Icons.view_module_rounded),
                      _chipFolga(_StatusFolgaFilter.disponiveis, 'Disponíveis para folga', Icons.event_available_rounded),
                      _chipFolga(_StatusFolgaFilter.usadas, 'Já usadas para folga', Icons.event_repeat_rounded),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // Painel-resumo Super Premium (Pontos em aberto / Folgas tiradas)
  // ============================================================
  //
  // Idêntico em comportamento ao painel do início (Audiências/Compromissos):
  // dois cards clicáveis com totais no período selecionado + filtros do
  // período (Mês atual · Mês anterior · Anual · Personalizado). Ao abrir: Anual.

  /// Calcula o intervalo de datas do resumo conforme o período selecionado.
  (DateTime, DateTime) _rangeForResumoPeriodo() {
    final now = DateTime.now();
    switch (_resumoPeriodo) {
      case _ResumoPeriodo.mesAtual:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
        return (start, end);
      case _ResumoPeriodo.mesAnterior:
        final start = DateTime(now.year, now.month - 1, 1);
        final end = DateTime(now.year, now.month, 0, 23, 59, 59, 999);
        return (start, end);
      case _ResumoPeriodo.anual:
        final start = DateTime(now.year, 1, 1);
        final end = DateTime(now.year, 12, 31, 23, 59, 59, 999);
        return (start, end);
      case _ResumoPeriodo.personalizado:
        final s = _resumoCustomStart ?? DateTime(now.year, now.month, 1);
        final e = _resumoCustomEnd ??
            DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
        return (
          DateTime(s.year, s.month, s.day),
          DateTime(e.year, e.month, e.day, 23, 59, 59, 999),
        );
    }
  }

  String _labelResumoPeriodo() {
    final (start, end) = _rangeForResumoPeriodo();
    switch (_resumoPeriodo) {
      case _ResumoPeriodo.mesAtual:
      case _ResumoPeriodo.mesAnterior:
        final monthYear = DateFormat('MMM/yyyy', 'pt_BR').format(start);
        return '$monthYear '
            '(${DateTimeFormats.dateBR.format(start)} a ${DateTimeFormats.dateBR.format(end)})';
      case _ResumoPeriodo.anual:
        return 'Ano ${start.year}';
      case _ResumoPeriodo.personalizado:
        return '${DateTimeFormats.dateBR.format(start)} a ${DateTimeFormats.dateBR.format(end)}';
    }
  }

  /// Pega pontuação (int seguro) de um doc de ocorrência.
  int _pontuacaoDe(Map<String, dynamic> data) {
    final v = data['pontuacao'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse((v ?? '0').toString()) ?? 0;
  }

  /// Card clicável (igual padrão Audiências do painel inicial).
  Widget _resumoCardClicavel({
    required IconData icon,
    required String label,
    required String valor,
    required String secondary,
    required Color background,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.9), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: AppColors.deepBlueDark),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.deepBlueDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                valor,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.deepBlueDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                secondary,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.deepBlueDark.withValues(alpha: 0.7),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Chip do filtro de período (Mês atual · Mês anterior · Anual ·
  /// Personalizado). **Super Premium**: alto contraste para o usuário
  /// distinguir claramente o que está selecionado.
  ///
  /// - **Selecionado**: pílula branca opaca com texto em azul-marinho forte.
  /// - **Não selecionado**: pílula branca translúcida (mas suficiente para
  ///   o texto branco em negrito ler bem) com borda mais marcada.
  ///   Antes era `alpha 0.18` (quase invisível) — agora `alpha 0.28` + borda
  ///   `alpha 0.9` + sombra leve, atendendo o padrão visual do app.
  Widget _chipResumoPeriodo(_ResumoPeriodo value, String label) {
    final selected = _resumoPeriodo == value;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _onSelectResumoPeriodo(value),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.9),
              width: selected ? 1.4 : 1.2,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: selected
                  ? AppColors.deepBlueDark
                  : Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  /// Mesma lógica do antigo `onSelected` do ChoiceChip, separada para o
  /// novo chip premium e para ser reutilizável por testes / atalhos.
  Future<void> _onSelectResumoPeriodo(_ResumoPeriodo value) async {
    if (value != _ResumoPeriodo.personalizado) {
      setState(() => _resumoPeriodo = value);
      return;
    }
    // Personalizado: usa o **picker inline** (mesmo padrão do Escalas) —
    // o usuário só preenche data inicial e final na mesma tela. Sem abrir
    // outro fluxo de tela cheia.
    setState(() {
      _resumoPeriodo = _ResumoPeriodo.personalizado;
      _resumoCustomExpanded = true;
      final now = DateTime.now();
      _resumoCustomStart ??= DateTime(now.year, now.month, 1);
      _resumoCustomEnd ??=
          DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
    });
  }

  /// Painel inline de "De" / "Até" exibido quando `Personalizado…` está
  /// selecionado. Mantém o usuário na **mesma tela**, sem abrir
  /// `showDateRangePicker` fullscreen.
  Widget _buildResumoPeriodoCustomInline() {
    final fmt = DateTimeFormats.dateBR;
    final now = DateTime.now();
    final ini = _resumoCustomStart ?? DateTime(now.year, now.month, 1);
    final fim = _resumoCustomEnd ??
        DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);

    Future<void> pickStart() async {
      final picked = await showDatePicker(
        context: context,
        initialDate: ini,
        firstDate: DateTime(2015),
        lastDate: DateTime(now.year + 5, 12, 31),
        helpText: 'Data inicial',
        cancelText: 'Cancelar',
        confirmText: 'OK',
      );
      if (picked == null || !mounted) return;
      setState(() {
        _resumoCustomStart = DateTime(picked.year, picked.month, picked.day);
        if (_resumoCustomEnd != null &&
            _resumoCustomEnd!.isBefore(_resumoCustomStart!)) {
          _resumoCustomEnd = DateTime(
              picked.year, picked.month, picked.day, 23, 59, 59, 999);
        }
      });
    }

    Future<void> pickEnd() async {
      final picked = await showDatePicker(
        context: context,
        initialDate: fim,
        firstDate: DateTime(2015),
        lastDate: DateTime(now.year + 5, 12, 31),
        helpText: 'Data final',
        cancelText: 'Cancelar',
        confirmText: 'OK',
      );
      if (picked == null || !mounted) return;
      setState(() {
        _resumoCustomEnd = DateTime(
            picked.year, picked.month, picked.day, 23, 59, 59, 999);
        if (_resumoCustomStart != null &&
            _resumoCustomStart!.isAfter(_resumoCustomEnd!)) {
          _resumoCustomStart =
              DateTime(picked.year, picked.month, picked.day);
        }
      });
    }

    Widget dateBox({
      required String label,
      required DateTime value,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.95)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.deepBlueDark.withValues(alpha: 0.7),
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.event_rounded,
                          size: 16, color: AppColors.deepBlueDark),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          fmt.format(value),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.deepBlueDark,
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
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              dateBox(label: 'De', value: ini, onTap: pickStart),
              const SizedBox(width: 8),
              dateBox(label: 'Até', value: fim, onTap: pickEnd),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _resumoCustomExpanded = false;
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.7)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  icon: const Icon(Icons.unfold_less_rounded, size: 18),
                  label: const Text(
                    'Ocultar',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _resumoPeriodo = _ResumoPeriodo.personalizado;
                    });
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.deepBlueDark,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text(
                    'Aplicar período',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Painel super premium no topo do módulo (Pontos em aberto / Folgas tiradas).
  Widget _buildResumoProdutividade() {
    final id = _userDocId;
    if (id.isEmpty) return const SizedBox.shrink();
    final (rangeStart, rangeEnd) = _rangeForResumoPeriodo();
    final periodLabel = _labelResumoPeriodo();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _ocorrenciasService.watch(id),
      builder: (context, snap) {
        int emAbertoQtde = 0;
        int emAbertoPontos = 0;
        int folgasPontos = 0;
        final folgaDays = <String>{};
        if (snap.hasData) {
          for (final d in snap.data!.docs) {
            final m = d.data();
            final fd = m['folgaDate'];
            final pts = _pontuacaoDe(m);
            if (fd == null) {
              // Em aberto — filtra pelo `date` da ocorrência.
              final dt = (m['date'] is Timestamp)
                  ? (m['date'] as Timestamp).toDate()
                  : null;
              if (dt == null) continue;
              if (dt.isBefore(rangeStart) || dt.isAfter(rangeEnd)) continue;
              emAbertoQtde++;
              emAbertoPontos += pts;
            } else {
              // Folga tirada — filtra pelo `folgaDate`.
              final fdt = (fd is Timestamp)
                  ? fd.toDate()
                  : (fd is DateTime ? fd : null);
              if (fdt == null) continue;
              if (fdt.isBefore(rangeStart) || fdt.isAfter(rangeEnd)) continue;
              folgasPontos += pts;
              folgaDays.add(
                  '${fdt.year}-${fdt.month.toString().padLeft(2, '0')}-${fdt.day.toString().padLeft(2, '0')}');
            }
          }
        }
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: AppColors.logoGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(_radiusLg),
            boxShadow: [
              BoxShadow(
                color: AppColors.deepBlueDark.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.insights_rounded,
                      color: Colors.white.withValues(alpha: 0.95), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Resumo de Produtividade',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          periodLabel,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.92),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _chipResumoPeriodo(_ResumoPeriodo.mesAtual, 'Mês atual'),
                    const SizedBox(width: 8),
                    _chipResumoPeriodo(
                        _ResumoPeriodo.mesAnterior, 'Mês anterior'),
                    const SizedBox(width: 8),
                    _chipResumoPeriodo(_ResumoPeriodo.anual, 'Anual'),
                    const SizedBox(width: 8),
                    _chipResumoPeriodo(
                        _ResumoPeriodo.personalizado, 'Personalizado…'),
                  ],
                ),
              ),
              if (_resumoPeriodo == _ResumoPeriodo.personalizado &&
                  _resumoCustomExpanded) ...[
                const SizedBox(height: 10),
                _buildResumoPeriodoCustomInline(),
              ],
              const SizedBox(height: 12),
              if (!snap.hasData)
                _resumoSkeleton()
              else
                Row(
                  children: [
                    Expanded(
                      child: _resumoCardClicavel(
                        icon: Icons.pending_actions_rounded,
                        label: 'Pontos em aberto',
                        valor: '$emAbertoPontos pts',
                        secondary:
                            '$emAbertoQtde ${emAbertoQtde == 1 ? 'ocorrência' : 'ocorrências'}',
                        background: Colors.white,
                        onTap: () => _abrirSheetResumo(
                          filter: ProdutividadeAbertoFilter.emAberto,
                          rangeStart: rangeStart,
                          rangeEnd: rangeEnd,
                          periodLabel: periodLabel,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _resumoCardClicavel(
                        icon: Icons.beach_access_rounded,
                        label: 'Folgas tiradas',
                        valor: '${folgaDays.length} ${folgaDays.length == 1 ? 'folga' : 'folgas'}',
                        secondary: '$folgasPontos pts utilizados',
                        background: Colors.white,
                        onTap: () => _abrirSheetResumo(
                          filter: ProdutividadeAbertoFilter.folgasTiradas,
                          rangeStart: rangeStart,
                          rangeEnd: rangeEnd,
                          periodLabel: periodLabel,
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.touch_app_rounded,
                      size: 13, color: Colors.white.withValues(alpha: 0.88)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Toque em cada cartão para abrir a lista. Mude o período acima para ver mês atual, anterior, anual ou personalizado.',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1.25,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _resumoSkeleton() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 86,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 86,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _abrirSheetResumo({
    required ProdutividadeAbertoFilter filter,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required String periodLabel,
  }) async {
    final id = _userDocId;
    if (id.isEmpty) return;
    await showProdutividadeEmAbertoSheet(
      context,
      userFsId: id,
      filter: filter,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      periodLabel: periodLabel,
      onAbrirModuloCompleto: () {
        // Já estamos dentro do módulo — apenas alinha o filtro com o sheet
        // aberto (mostra na lista o mesmo conjunto de itens).
        if (mounted) {
          setState(() {
            _statusFolga = filter == ProdutividadeAbertoFilter.emAberto
                ? _StatusFolgaFilter.disponiveis
                : _StatusFolgaFilter.usadas;
          });
          // Scroll para o topo da seção «Ocorrências».
          widget.shellScrollController?.animateTo(
            0,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
          );
        }
      },
      buildTile: (ctx, doc) => _resumoTile(doc),
    );
  }

  /// Tile compacto da lista do sheet (não traz edição/exclusão — só leitura).
  Widget _resumoTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final dt = (data['date'] is Timestamp)
        ? (data['date'] as Timestamp).toDate()
        : null;
    final folga = (data['folgaDate'] is Timestamp)
        ? (data['folgaDate'] as Timestamp).toDate()
        : null;
    final pts = _pontuacaoDe(data);
    final natureza = _naturezaLabelFromDoc(data);
    final temFolga = folga != null;
    final accent =
        temFolga ? AppColors.logoOrange : AppColors.accent;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: accent.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(
                temFolga
                    ? Icons.beach_access_rounded
                    : Icons.task_alt_rounded,
                color: accent,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    natureza.isEmpty ? 'Ocorrência' : natureza,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      fontSize: 13.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    temFolga
                        ? 'Folga em ${formatDateOrDash(folga)} · ocorrência ${formatDateOrDash(dt)}'
                        : 'Data: ${formatDateOrDash(dt)}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$pts pts',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: accent,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAcoesRapidasPremium() {
    // Pedido do usuário: em mobile (Android/iOS/web estreita) os botões
    // têm de ficar 100% visíveis — antes o FAB «Nova ocorrência» cobria o
    // segundo botão. Empilhamos em Column (full-width) em telas
    // estreitas e mantemos lado a lado só em telas largas.
    return LayoutBuilder(
      builder: (ctx, c) {
        // Largura útil dentro do card (descontando o padding 14 + 14).
        final innerWidth = c.maxWidth - 28;
        // Cada botão precisa de ~190px para mostrar ícone + label inteiro.
        // Abaixo disso (mobile) vamos para Column.
        final useColumn = innerWidth < 380;

        final pdfBtn = FilledButton.icon(
          onPressed: _exportarPdfProdutividadeListaSuperPremium,
          icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
          label: const Text(
            'PDF — Super Premium',
            style: TextStyle(fontWeight: FontWeight.w800),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.logoOrange,
            foregroundColor: Colors.white,
            elevation: 2,
            shadowColor:
                AppColors.logoOrange.withValues(alpha: 0.45),
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );

        final naturezasBtn = FilledButton.icon(
          onPressed: () => _abrirGerenciarNaturezas(context),
          icon: const Icon(Icons.interests_rounded, size: 20),
          label: const Text(
            'Editar/Adicionar naturezas',
            style: TextStyle(fontWeight: FontWeight.w800),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            elevation: 2,
            shadowColor: AppColors.accent.withValues(alpha: 0.45),
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );

        return Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF8FAFF), Color(0xFFF1F5FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(_radiusLg),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: AppColors.deepBlueDark.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: useColumn
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    pdfBtn,
                    const SizedBox(height: 10),
                    naturezasBtn,
                  ],
                )
              : Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [pdfBtn, naturezasBtn],
                ),
        );
      },
    );
  }

  Widget _chipFolga(_StatusFolgaFilter value, String label, IconData chipIcon) {
    final selected = _statusFolga == value;
    final (Color accent, Color soft) = switch (value) {
      _StatusFolgaFilter.todas => (
          AppColors.primary,
          AppColors.primary.withValues(alpha: 0.14),
        ),
      _StatusFolgaFilter.disponiveis => (
          AppColors.accent,
          AppColors.accent.withValues(alpha: 0.16),
        ),
      _StatusFolgaFilter.usadas => (
          AppColors.logoOrange,
          AppColors.logoOrange.withValues(alpha: 0.18),
        ),
    };
    return FilterChip(
      avatar: Icon(
        chipIcon,
        size: 18,
        color: selected ? accent : AppColors.textSecondary,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          color: selected ? accent : AppColors.textSecondary,
          fontSize: 13,
        ),
      ),
      selected: selected,
      onSelected: (_) => setState(() {
        _statusFolga = value;
        _selecionadosFolga.clear();
        _selecionadosLimparFolga.clear();
      }),
      selectedColor: soft,
      checkmarkColor: accent,
      showCheckmark: true,
      side: BorderSide(
        color: selected ? accent : AppColors.textMuted.withValues(alpha: 0.45),
        width: selected ? 2 : 1,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    );
  }

  Widget _buildCardFolga(List<Map<String, dynamic>> allOcorrencias) {
    if (_selecionadosFolga.isEmpty) return const SizedBox.shrink();
    final selecionadas = allOcorrencias.where((e) => _selecionadosFolga.contains((e['id'] ?? '').toString())).toList();
    int totalPontos = 0;
    for (final e in selecionadas) {
      totalPontos += (e['pontuacao'] is int) ? e['pontuacao'] as int : int.tryParse((e['pontuacao'] ?? '0').toString()) ?? 0;
    }
    return FutureBuilder<int>(
      future: ProdutividadeConfigService().getPontuacaoParaFolga(_userDocId),
      builder: (context, snap) {
        final pontuacaoParaFolga = snap.data ?? ProdutividadeConfigService.defaultPontuacaoParaFolga;
        final restantes = totalPontos - pontuacaoParaFolga;
        final temSobra = restantes > 0;
        return Container(
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(_radius),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.25), width: 1),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_selecionadosFolga.length} ocorrência(s) selecionada(s)',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Total: $totalPontos pts',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Para 1 folga: $pontuacaoParaFolga pts (parâmetro em Configurações)',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (temSobra) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.orange.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Sobrando $restantes pts.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.orange.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Será gerado automaticamente um novo lançamento com a diferença dos pontos, vinculado à folga e às ocorrências utilizadas.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange.shade800,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _buildFolgaCalendarColorSection(),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 420;
                    final dateField = DateFieldWithCalendarOrManual(
                      value: _dataFolgaEscolhida ?? DateTime.now(),
                      onChanged: (d) => setState(() => _dataFolgaEscolhida = d),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                      label: 'Data da folga',
                    );
                    final pdfBtn = FilledButton.icon(
                      onPressed: (_dataFolgaEscolhida != null &&
                              totalPontos >= pontuacaoParaFolga)
                          ? () => _abrirConfirmacaoFolgaPremium(
                                pontuacaoParaFolga: pontuacaoParaFolga,
                                totalPontos: totalPontos,
                              )
                          : null,
                      icon: const Icon(Icons.event_available_rounded, size: 22),
                      label: Text(
                        narrow ? 'Confirmar folga' : 'Revisar e confirmar folga',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.logoOrange,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shadowColor: AppColors.logoOrange.withValues(alpha: 0.45),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    );
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          dateField,
                          const SizedBox(height: 12),
                          pdfBtn,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: dateField),
                        const SizedBox(width: 12),
                        pdfBtn,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _selecionadosFolga.clear()),
                    icon: Icon(Icons.layers_clear_rounded,
                        size: 20, color: AppColors.secondary.withValues(alpha: 0.9)),
                    label: const Text(
                      'Limpar seleção',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: BorderSide(
                        color: AppColors.secondary.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Relatório de produtividade/ocorrências: exporta exatamente o que está na lista (grid), sem novo filtro de período.
  Future<void> _exportarPdfProdutividadeListaSuperPremium() async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    if (_userDocId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A sincronizar sessão… tente de novo em instantes.')),
      );
      return;
    }

    final filtro = switch (_statusFolga) {
      _StatusFolgaFilter.todas => 'todos',
      _StatusFolgaFilter.disponiveis => 'sem_folga',
      _StatusFolgaFilter.usadas => 'usadas_folga',
    };
    final filtroSufixo = filtro == 'todos'
        ? ''
        : filtro == 'sem_folga'
            ? 'sem folga'
            : 'usadas folga';

    try {
      final todas = await _ocorrenciasService.getAll(_userDocId);
      if (!mounted) return;
      final filtrada = _aplicarFiltroFolga(todas);
      if (filtrada.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nada a exportar: não há ocorrências com o filtro «Status da folga» atual.'),
          ),
        );
        return;
      }
      DateTime dateStart = _toDate(filtrada.first['date']);
      DateTime dateEnd = dateStart;
      for (final e in filtrada) {
        final d = _toDate(e['date']);
        if (d.isBefore(dateStart)) dateStart = d;
        if (d.isAfter(dateEnd)) dateEnd = d;
      }
      final periodLabel =
          '${DateTimeFormats.dateBR.format(dateStart)} a ${DateTimeFormats.dateBR.format(dateEnd)} · ${_statusFolga == _StatusFolgaFilter.todas ? 'Todas' : _statusFolga == _StatusFolgaFilter.disponiveis ? 'Disponíveis para folga' : 'Já usadas para folga'}';
      final part = ProdutividadeOcorrenciasPdfPartition.partition(filtrada);
      final filenameBase = RelatorioService.reportFilenameFromPeriod(
        'produtividade_ocorrencias',
        dateStart,
        dateEnd,
        filtroSufixo.isEmpty ? null : filtroSufixo,
      );
      final (bytes, _) = await RelatorioService.buildRelatorioProdutividadeOcorrenciasBytes(
        periodo: periodLabel,
        semFolga: part.semFolga,
        usadasFolga: part.usadasFolga,
        filtro: filtro,
        suggestedFilename: filenameBase,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ReportPreviewScreen(bytes: bytes, filename: filenameBase),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao gerar PDF: ${e.toString().split('\n').first}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _gerarPdfSolicitacaoFolga() async {
    if (_dataFolgaEscolhida == null || _selecionadosFolga.isEmpty) return;
    final dataFolga = _dataFolgaEscolhida!;
    final dataFolgaStr = DateTimeFormats.dateBR.format(dataFolga);
    final diaSemana = _diaSemana(dataFolga);

    final pontuacaoParaFolga = await ProdutividadeConfigService().getPontuacaoParaFolga(_userDocId);

    final all = await _ocorrenciasService.getAll(_userDocId);
    final selecionadas = all.where((e) => _selecionadosFolga.contains((e['id'] ?? '').toString())).toList();
    if (selecionadas.isEmpty) return;

    int totalPontos = 0;
    for (final e in selecionadas) {
      totalPontos += (e['pontuacao'] is int) ? e['pontuacao'] as int : int.tryParse((e['pontuacao'] ?? '0').toString()) ?? 0;
    }

    // Só aceitar gerar se a seleção atingir a pontuação configurada
    if (totalPontos < pontuacaoParaFolga) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Selecione ocorrências que somem pelo menos $pontuacaoParaFolga pts (configurações). '
              'Total selecionado: $totalPontos pts.',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    // Para o PDF usamos exatamente pontuacaoParaFolga (o que efetivamente é consumido na folga)
    final pontosParaPdf = totalPontos > pontuacaoParaFolga ? pontuacaoParaFolga : totalPontos;

    final ocorrenciasParaPdf = selecionadas.map((e) {
      final date = e['date'];
      return {
        'date': date is Timestamp ? date.toDate() : date,
        'numeroOcorrencia': e['numeroOcorrencia'] ?? '',
        'naturezaLabel': e['naturezaLabel'] ?? '',
        'pontuacao': e['pontuacao'] ?? 0,
      };
    }).toList();

    final (bytes, filename) = await RelatorioService.buildRelatorioSolicitacaoFolgaBytes(
      dataFolga: dataFolgaStr,
      diaSemana: diaSemana,
      ocorrencias: ocorrenciasParaPdf,
      totalPontos: pontosParaPdf,
    );
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ReportPreviewScreen(bytes: bytes, filename: filename),
      ),
    );

    await _ocorrenciasService.marcarFolga(
      _userDocId,
      _selecionadosFolga.toList(),
      dataFolga,
      folgaCalendarColorHex: _folgaCalendarColorHex,
    );

    await ProdutividadeScaleMirrorService.upsert(
      userDocId: _userDocId,
      folgaDate: dataFolga,
      colorHex: _folgaCalendarColorHex,
    );

    // Se sobrar pontos, criar lançamento automático com observação detalhada
    final restantes = totalPontos - pontuacaoParaFolga;
    if (restantes > 0 && selecionadas.isNotEmpty) {
      final primeira = selecionadas.first;
      final dataFolgaStr = DateTimeFormats.dateBR.format(dataFolga);
      final ocorrenciasDesc = selecionadas.map((o) {
        final data = o['date'];
        final dt = data is Timestamp ? data.toDate() : (data is DateTime ? data : null);
        final dataStr = dt != null ? DateTimeFormats.dateBR.format(dt) : '-';
        final num = (o['numeroOcorrencia'] ?? '').toString();
        final natureza = (o['naturezaLabel'] ?? '').toString();
        final pts = (o['pontuacao'] is int) ? o['pontuacao'] as int : int.tryParse((o['pontuacao'] ?? '0').toString()) ?? 0;
        return '- $dataStr | $natureza | N° $num | $pts pts';
      }).join('\n');
      final observacao = 'Vinculado à sobra de pontos referente à folga de $dataFolgaStr.\n\n'
          'Ocorrências utilizadas para essa folga:\n$ocorrenciasDesc\n\n'
          'Total de pontos usado na folga: $pontuacaoParaFolga pts\n'
          'Pontos que sobraram: $restantes pts';
      await _ocorrenciasService.add(
        _userDocId,
        date: DateTime.now(),
        pontuacao: restantes,
        numeroOcorrencia: 'Restantes da folga - $dataFolgaStr',
        naturezaId: (primeira['naturezaId'] ?? 'restantes').toString(),
        naturezaLabel: 'Restantes pontos da ocorrência',
        observacao: observacao,
      );
    }

    if (mounted) {
      setState(() {
        _selecionadosFolga.clear();
        _dataFolgaEscolhida = DateTime.now(); // mantém data padrão para próxima seleção (evita botão desabilitado)
      });
      final msg = restantes > 0
          ? 'PDF gerado, folga no calendário de Escalas, ocorrências marcadas e $restantes pts restantes criados como nova ocorrência.'
          : 'PDF gerado, folga registada no calendário de Escalas e ocorrências marcadas.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Widget _buildObservacaoTile(dynamic observacao) {
    final s = (observacao ?? '').toString().trim();
    if (s.isEmpty) return const SizedBox.shrink();
    return _ObservacaoExpansivel(texto: s);
  }

  Future<({Uint8List bytes, String fileName, String contentType, String extension})?> _pickAnexoOcorrencia(BuildContext context) async {
    // Mesmo padrão do módulo financeiro: pickFiles sem FileType.custom (que bugga
    // PDFs no Android/Web) e validamos a extensão depois, no código.
    final picked = await FilePicker.platform.pickFiles(withData: true);
    if (picked == null || picked.files.isEmpty) return null;
    final file = picked.files.first;
    String ext = (file.extension ?? '').toLowerCase().replaceAll('jpeg', 'jpg');
    if (ext.isEmpty) {
      // Fallback: extrai extensão a partir do nome do arquivo (alguns provedores
      // — Drive, iOS Files — não preenchem `extension`).
      final name = file.name.toLowerCase();
      final dot = name.lastIndexOf('.');
      if (dot >= 0 && dot < name.length - 1) {
        ext = name.substring(dot + 1).replaceAll('jpeg', 'jpg');
      }
    }
    final raw = file.bytes;
    final mimeRaw = (file.path ?? '').toLowerCase();
    if (raw == null || raw.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível ler o arquivo. Tente outro ou um tamanho menor.')),
        );
      }
      return null;
    }
    if (!_anexoAllowedExtensions.contains(ext) || mimeRaw.endsWith('.mp4') || mimeRaw.endsWith('.mov') || mimeRaw.endsWith('.avi') || mimeRaw.endsWith('.mkv') || mimeRaw.endsWith('.webm')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Apenas PDF, PNG ou JPG. Vídeos e outros formatos não são aceitos.')),
        );
      }
      return null;
    }

    if (ext == 'pdf') {
      // Servidor (Storage Rules) usa `<` estrito em 5MB — então no cliente
      // precisamos rejeitar `>=` para evitar 403 silencioso ao subir 5MB exatos.
      if (raw.length >= _anexoMaxBytes) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PDF excede 5MB. Envie uma versão mais leve.')),
          );
        }
        return null;
      }
      return (
        bytes: raw,
        fileName: file.name.isEmpty ? 'ocorrencia.pdf' : file.name,
        contentType: 'application/pdf',
        extension: 'pdf',
      );
    }

    // Compressão pesada roda em isolate para não travar a UI no Android (responsivo).
    final compressed = await compute(_compressImageInIsolate, raw);
    if (compressed == null || compressed.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível processar a imagem selecionada.')),
        );
      }
      return null;
    }
    if (compressed.length >= _anexoMaxBytes) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Imagem final excede 5MB. Escolha outra imagem.')),
        );
      }
      return null;
    }
    final normalizedName = file.name.isEmpty ? 'ocorrencia.jpg' : file.name.replaceAll(RegExp(r'\.[^.]+$'), '.jpg');
    return (
      bytes: compressed,
      fileName: normalizedName,
      contentType: 'image/jpeg',
      extension: 'jpg',
    );
  }

  Future<Map<String, dynamic>> _uploadAnexoOcorrencia({
    required String docId,
    required Uint8List bytes,
    required String extension,
    required String fileName,
    required String contentType,
  }) async {
    final storagePath = 'users/${_userDocId}/ocorrencias/$docId/anexo.$extension';
    final ref = FirebaseStorage.instance.ref(storagePath);
    try {
      await ref.putData(
        bytes,
        SettableMetadata(contentType: contentType),
      );
      final url = await ref.getDownloadURL();
      return {
        'anexoUrl': url,
        'anexoFileName': fileName,
        'anexoContentType': contentType,
        'anexoSizeBytes': bytes.length,
        'anexoStoragePath': storagePath,
      };
    } on FirebaseException catch (e) {
      // Traduz erros do Storage para mensagens claras (PT-BR) — evita o
      // genérico "[firebase_storage/...]" aparecendo cru pro usuário.
      final code = (e.code).toLowerCase();
      String msg;
      if (code.contains('unauthorized') || code.contains('permission')) {
        msg = 'Sem permissão para anexar agora. Verifique sua licença e tente novamente.';
      } else if (code.contains('canceled') || code.contains('cancelled')) {
        msg = 'Envio cancelado.';
      } else if (code.contains('quota') || code.contains('exceeded')) {
        msg = 'Limite de armazenamento atingido. Tente um arquivo menor.';
      } else if (code.contains('retry') || code.contains('network') || code.contains('unavailable')) {
        msg = 'Falha de rede ao enviar o anexo. Verifique sua conexão e tente novamente.';
      } else {
        msg = 'Erro ao enviar anexo: ${e.message ?? e.code}';
      }
      throw _AnexoUploadException(msg);
    } catch (e) {
      throw _AnexoUploadException('Erro inesperado ao enviar anexo: $e');
    }
  }

  bool _isImageAnexo({
    required String url,
    required String fileName,
    required String contentType,
  }) {
    final ct = contentType.toLowerCase();
    if (ct.startsWith('image/')) return true;
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return true;
    }
    final lu = url.toLowerCase();
    return lu.contains('.png') || lu.contains('.jpg') || lu.contains('.jpeg');
  }

  Future<void> _trocarAnexoOcorrencia(String docId, Map<String, dynamic> e) async {
    final picked = await _pickAnexoOcorrencia(context);
    if (picked == null) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enviando anexo...'), duration: Duration(seconds: 2)),
      );
    }

    Map<String, dynamic> anexoPayload;
    try {
      anexoPayload = await _uploadAnexoOcorrencia(
        docId: docId,
        bytes: picked.bytes,
        extension: picked.extension,
        fileName: picked.fileName,
        contentType: picked.contentType,
      );
    } on _AnexoUploadException catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(err.userMessage),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 5),
            ),
          );
      }
      return;
    }

    // Só remove o arquivo antigo do Storage depois que o novo subiu (defensivo).
    final oldPath = (e['anexoStoragePath'] ?? '').toString().trim();
    final newPath = (anexoPayload['anexoStoragePath'] ?? '').toString().trim();
    if (oldPath.isNotEmpty && oldPath != newPath) {
      try {
        await FirebaseStorage.instance.ref(oldPath).delete();
      } catch (_) {}
    }

    try {
      final date = (e['date'] is Timestamp) ? (e['date'] as Timestamp).toDate() : DateTime.now();
      final pontuacao = (e['pontuacao'] as int?) ?? 0;
      await _ocorrenciasService.update(
        _userDocId,
        docId,
        date: date,
        pontuacao: pontuacao,
        numeroOcorrencia: (e['numeroOcorrencia'] ?? '').toString(),
        naturezaId: (e['naturezaId'] ?? '').toString(),
        naturezaLabel: (e['naturezaLabel'] ?? '').toString(),
        anexoUrl: (anexoPayload['anexoUrl'] ?? '').toString(),
        anexoFileName: (anexoPayload['anexoFileName'] ?? '').toString(),
        anexoContentType: (anexoPayload['anexoContentType'] ?? '').toString(),
        anexoSizeBytes: (anexoPayload['anexoSizeBytes'] as int?) ?? 0,
        anexoStoragePath: (anexoPayload['anexoStoragePath'] ?? '').toString(),
      );
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Anexo enviado, mas falhou ao salvar no banco: $err'),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 5),
            ),
          );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Anexo atualizado com sucesso.')),
        );
    }
  }

  Future<void> _removerAnexoOcorrencia(String docId, Map<String, dynamic> e) async {
    final oldPath = (e['anexoStoragePath'] ?? '').toString().trim();
    // Storage delete é "best effort": se o arquivo já não existe ou houve falha de rede,
    // ainda assim limpamos os campos no Firestore para a UX ficar consistente.
    if (oldPath.isNotEmpty) {
      try {
        await FirebaseStorage.instance.ref(oldPath).delete();
      } catch (_) {}
    }
    try {
      final date = (e['date'] is Timestamp) ? (e['date'] as Timestamp).toDate() : DateTime.now();
      final pontuacao = (e['pontuacao'] as int?) ?? 0;
      await _ocorrenciasService.update(
        _userDocId,
        docId,
        date: date,
        pontuacao: pontuacao,
        numeroOcorrencia: (e['numeroOcorrencia'] ?? '').toString(),
        naturezaId: (e['naturezaId'] ?? '').toString(),
        naturezaLabel: (e['naturezaLabel'] ?? '').toString(),
        limparAnexo: true,
      );
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível atualizar a ocorrência: $err'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anexo removido.')),
      );
    }
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.accent, AppColors.primary],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tileOcorrencia(Map<String, dynamic> e) {
    final id = (e['id'] ?? '').toString();
    final dataDisplay = _formatDateAny(e['date'] ?? e['createdAt']);
    final naturezaDisplay = _naturezaLabelFromDoc(e);
    final numeroDisplay =
        (e['numeroOcorrencia'] ?? e['numero'] ?? '').toString().trim();
    final temFolga = e['folgaDate'] != null;
    final folgaStr = temFolga ? _formatDateAny(e['folgaDate']) : null;
    final selecionado = _selecionadosFolga.contains(id);
    final barColor = temFolga ? AppColors.success : AppColors.accent;
    final anexoUrl = (e['anexoUrl'] ?? '').toString().trim();
    final anexoFileName = (e['anexoFileName'] ?? 'Anexo ocorrência').toString();
    final anexoContentType = (e['anexoContentType'] ?? '').toString();
    final hasAnexo = anexoUrl.isNotEmpty;
    final showImageThumb = hasAnexo &&
        _isImageAnexo(url: anexoUrl, fileName: anexoFileName, contentType: anexoContentType);

    return RepaintBoundary(
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_radiusLg),
        // Faixa de estado à esquerda (evita Row + IntrinsicHeight + Expanded — quebra layout Web/iOS em alguns motores).
        border: Border(
          left: BorderSide(color: barColor, width: 5),
          top: BorderSide(color: AppColors.deepBlueDark.withValues(alpha: 0.06)),
          right: BorderSide(color: AppColors.deepBlueDark.withValues(alpha: 0.06)),
          bottom: BorderSide(color: AppColors.deepBlueDark.withValues(alpha: 0.06)),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlueDark.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radiusLg),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 10, 14),
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  final compactMobile = constraints.maxWidth < 430;

                          final trailingScore = Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.primary.withValues(alpha: 0.12),
                                  AppColors.accent.withValues(alpha: 0.1),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Text(
                              '${e['pontuacao'] ?? 0} pts',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primary,
                              ),
                            ),
                          );

                          final trailingActions = widget.profile.hasActiveLicense
                              ? Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  alignment: compactMobile
                                      ? WrapAlignment.start
                                      : WrapAlignment.end,
                                  children: [
                                    Tooltip(
                                      message: hasAnexo
                                          ? 'Trocar anexo (PDF / print)'
                                          : 'Anexar PDF ou print',
                                      child: FilledButton.tonal(
                                        onPressed: () =>
                                            _trocarAnexoOcorrencia(id, e),
                                        style: FilledButton.styleFrom(
                                          minimumSize: const Size(48, 48),
                                          padding: EdgeInsets.zero,
                                          backgroundColor: AppColors.accent
                                              .withValues(alpha: 0.12),
                                          foregroundColor: AppColors.accent,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.attach_file_rounded,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                    Tooltip(
                                      message: 'Ver comprovante',
                                      child: FilledButton.tonal(
                                        onPressed: hasAnexo
                                            ? () => mostrarAnexoNaMesmaTela(
                                                  context,
                                                  url: anexoUrl,
                                                  fileName: anexoFileName,
                                                )
                                            : null,
                                        style: FilledButton.styleFrom(
                                          minimumSize: const Size(48, 48),
                                          padding: EdgeInsets.zero,
                                          backgroundColor: AppColors.primary
                                              .withValues(alpha: 0.12),
                                          foregroundColor: AppColors.primary,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.visibility_rounded,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                    Tooltip(
                                      message: 'Editar',
                                      child: FilledButton.tonal(
                                        onPressed: () =>
                                            _abrirEditarOcorrencia(
                                                context, id, e),
                                        style: FilledButton.styleFrom(
                                          minimumSize: const Size(48, 48),
                                          padding: EdgeInsets.zero,
                                          backgroundColor: AppColors.primary
                                              .withValues(alpha: 0.12),
                                          foregroundColor: AppColors.primary,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.edit_note_rounded,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                    Tooltip(
                                      message: hasAnexo
                                          ? 'Remover anexo'
                                          : 'Sem anexo',
                                      child: FilledButton.tonal(
                                        onPressed: hasAnexo
                                            ? () => _removerAnexoOcorrencia(
                                                  id,
                                                  e,
                                                )
                                            : null,
                                        style: FilledButton.styleFrom(
                                          minimumSize: const Size(48, 48),
                                          padding: EdgeInsets.zero,
                                          backgroundColor: AppColors.amber
                                              .withValues(alpha: 0.18),
                                          foregroundColor:
                                              AppColors.deepBlueDark,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.link_off_rounded,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                    Tooltip(
                                      message: 'Excluir',
                                      child: FilledButton.tonal(
                                        onPressed: () =>
                                            _confirmarRemover(id, e),
                                        style: FilledButton.styleFrom(
                                          minimumSize: const Size(48, 48),
                                          padding: EdgeInsets.zero,
                                          backgroundColor: AppColors.error
                                              .withValues(alpha: 0.12),
                                          foregroundColor: AppColors.error,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.delete_forever_rounded,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : const SizedBox.shrink();

                          final emGridUsadas = _statusFolga == _StatusFolgaFilter.usadas;
                          final leadingMarker = widget.profile.hasActiveLicense && !temFolga
                              ? Padding(
                                  padding:
                                      const EdgeInsets.only(right: 4, top: 2),
                                  child: Checkbox(
                                    value: selecionado,
                                    onChanged: (v) {
                                      setState(() {
                                        if (v == true) {
                                          _selecionadosFolga.add(id);
                                        } else {
                                          _selecionadosFolga.remove(id);
                                        }
                                      });
                                    },
                                    activeColor: AppColors.primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                )
                              : (temFolga && emGridUsadas && widget.profile.hasActiveLicense)
                                  ? Padding(
                                      padding:
                                          const EdgeInsets.only(right: 4, top: 2),
                                      child: Checkbox(
                                        value: _selecionadosLimparFolga.contains(id),
                                        onChanged: (v) {
                                          setState(() {
                                            if (v == true) {
                                              _selecionadosLimparFolga.add(id);
                                            } else {
                                              _selecionadosLimparFolga.remove(id);
                                            }
                                          });
                                        },
                                        activeColor: AppColors.logoOrange,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                      ),
                                    )
                                  : (temFolga
                                      ? Padding(
                                          padding: const EdgeInsets.only(
                                              right: 8, top: 4),
                                          child: Icon(
                                            Icons.verified_rounded,
                                            color: AppColors.success,
                                            size: 28,
                                          ),
                                        )
                                      : const SizedBox.shrink());

                          final infoColumn = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dataDisplay.isEmpty ? 'Data não informada' : dataDisplay,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                naturezaDisplay,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (numeroDisplay.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Nº $numeroDisplay',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              if (temFolga && folgaStr != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.success
                                              .withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          'Folga: $folgaStr',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.success,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      if (widget.profile.hasActiveLicense &&
                                          _statusFolga != _StatusFolgaFilter.usadas)
                                        TextButton(
                                          onPressed: () => _confirmarELimparFolgaEmIds([id]),
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                          child: const Text(
                                            'Limpar folga',
                                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              _buildObservacaoTile(e['observacao']),
                              if (hasAnexo)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: const Text(
                                              'Anexo comprimido',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (showImageThumb) ...[
                                        const SizedBox(height: 8),
                                        InkWell(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          onTap: () => mostrarAnexoNaMesmaTela(
                                            context,
                                            url: anexoUrl,
                                            fileName: anexoFileName,
                                          ),
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            child: Container(
                                              width: 120,
                                              height: 88,
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade100,
                                                border: Border.all(
                                                  color: AppColors.primary
                                                      .withValues(alpha: 0.2),
                                                ),
                                              ),
                                              child: Image.network(
                                                anexoUrl,
                                                fit: BoxFit.cover,
                                                // Decodifica em tamanho reduzido (thumb) para poupar memória/GPU no Android.
                                                cacheWidth: 240,
                                                cacheHeight: 176,
                                                errorBuilder: (_, __, ___) =>
                                                    const Center(
                                                  child: Icon(
                                                    Icons
                                                        .image_not_supported_rounded,
                                                    size: 20,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                            ],
                          );

                          if (compactMobile) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    leadingMarker,
                                    Expanded(
                                      child: ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(minWidth: 0),
                                        child: infoColumn,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: trailingScore,
                                ),
                                if (widget.profile.hasActiveLicense) ...[
                                  const SizedBox(height: 10),
                                  trailingActions,
                                ],
                              ],
                            );
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              leadingMarker,
                              Expanded(
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(minWidth: 0),
                                  child: infoColumn,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  trailingScore,
                                  if (widget.profile.hasActiveLicense) ...[
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: 156,
                                      child: trailingActions,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _emptyCard(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_radiusLg),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlueDark.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.12),
                  AppColors.accent.withValues(alpha: 0.1),
                ],
              ),
            ),
            child: Icon(
              Icons.post_add_rounded,
              size: 40,
              color: AppColors.primary.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirFormNovaOcorrencia(BuildContext context) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    if (_loadingNaturezas || _naturezas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Carregue as naturezas antes.')),
      );
      return;
    }
    DateTime date = DateTime.now();
    OcorrenciaNatureza? naturezaSelecionada = _naturezas.isNotEmpty ? _naturezas.first : null;
    final numeroCtrl = TextEditingController();
    final observacaoCtrl = TextEditingController();
    Uint8List? anexoBytes;
    String? anexoFileName;
    String? anexoContentType;
    String? anexoExtension;

    final ok = await showDialog<bool>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final pontuacao = naturezaSelecionada?.pontos ?? 0;
          final fieldPad = KeyboardFormInsets.dialogFieldScrollPadding(
            ctx,
            footerEstimate: 140,
          );
          return wrapKeyboardAwareDialog(
            ctx,
            AlertDialog(
            scrollable: true,
            insetPadding: keyboardAwareDialogInsetPadding(ctx),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            titlePadding: EdgeInsets.zero,
            title: _dialogGradientTitle(
              icon: Icons.post_add_rounded,
              title: 'Nova ocorrência',
              subtitle: 'Lançamento — data, natureza e número (RAI)',
            ),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            content: KeyboardAwareDialogScrollBody(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 280, maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildCampoDataForm(ctx, date, (d) => setDialogState(() => date = d)),
                    const SizedBox(height: 20),
                    _buildLabelObrigatorio('Natureza'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<OcorrenciaNatureza?>(
                      value: naturezaSelecionada,
                      isExpanded: true,
                      decoration: _inputDecoration('Selecione a natureza'),
                      selectedItemBuilder: (context) => [
                        ..._naturezas.map(
                          (n) => Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              n.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              softWrap: true,
                            ),
                          ),
                        ),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Adicionar nova natureza'),
                        ),
                      ],
                      items: [
                        ..._naturezas.map((n) => DropdownMenuItem(
                              value: n,
                              child: Text(n.label, overflow: TextOverflow.ellipsis, maxLines: 2, softWrap: true),
                            )),
                        DropdownMenuItem<OcorrenciaNatureza?>(
                          value: null,
                          child: Row(
                            children: [
                              Icon(Icons.add_rounded, size: 18, color: AppColors.primary),
                              const SizedBox(width: 8),
                              const Text('Adicionar nova natureza'),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (v) async {
                        if (v == null) {
                          final nova = await _dialogNovaNatureza(ctx);
                          if (nova != null && ctx.mounted) {
                            await _naturezasService.add(_userDocId, nova.label, nova.pontos);
                            await _carregarNaturezas();
                            if (ctx.mounted) setDialogState(() => naturezaSelecionada = _naturezas.isNotEmpty ? _naturezas.last : null);
                          }
                          return;
                        }
                        setDialogState(() => naturezaSelecionada = v);
                      },
                    ),
                    const SizedBox(height: 20),
                    _buildLabelObrigatorio('Pontuação (somente leitura)'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.star_rounded, color: AppColors.amber, size: 22),
                          const SizedBox(width: 12),
                          Text('${pontuacao} pts', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '(definido na natureza)',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              softWrap: true,
                              maxLines: 3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildLabelObrigatorio('Número da ocorrência (RAI)'),
                    const SizedBox(height: 8),
                    FastTextField(
                      controller: numeroCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      scrollPadding: fieldPad,
                      decoration: _inputDecoration('Apenas números'),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 20),
                    _buildLabelOpcional('Observação'),
                    const SizedBox(height: 8),
                    FastTextField(
                      controller: observacaoCtrl,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      minLines: 2,
                      maxLines: 4,
                      scrollPadding: fieldPad,
                      decoration: _inputDecoration('Ex.: detalhes adicionais da ocorrência'),
                    ),
                    const SizedBox(height: 20),
                    _buildLabelOpcional('Anexo (PDF ou print)'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await _pickAnexoOcorrencia(ctx);
                              if (picked == null) return;
                              setDialogState(() {
                                anexoBytes = picked.bytes;
                                anexoFileName = picked.fileName;
                                anexoContentType = picked.contentType;
                                anexoExtension = picked.extension;
                              });
                            },
                            icon: const Icon(Icons.attach_file_rounded, size: 18),
                            label: Text(
                              anexoFileName == null ? 'Anexar arquivo' : 'Trocar arquivo',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        if (anexoBytes != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => setDialogState(() {
                              anexoBytes = null;
                              anexoFileName = null;
                              anexoContentType = null;
                              anexoExtension = null;
                            }),
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Remover anexo',
                          ),
                        ],
                      ],
                    ),
                    if (anexoFileName != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '$anexoFileName (${((anexoBytes?.length ?? 0) / 1024).toStringAsFixed(0)} KB)',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actions: [
              OutlinedButton.icon(
                onPressed: () => Navigator.of(ctx).pop(false),
                icon: Icon(Icons.close_rounded,
                    size: 18, color: AppColors.textSecondary.withValues(alpha: 0.95)),
                label: const Text(
                  'Cancelar',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: BorderSide(
                    color: AppColors.textMuted.withValues(alpha: 0.45),
                    width: 1.4,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () {
                  if (naturezaSelecionada == null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Selecione a natureza.')));
                    return;
                  }
                  final numStr = numeroCtrl.text.trim();
                  if (numStr.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Informe o número da ocorrência.')));
                    return;
                  }
                  Navigator.of(ctx).pop(true);
                },
                icon: const Icon(Icons.check_circle_rounded, size: 20),
                label: const Text(
                  'Salvar ocorrência',
                  style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.2),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 3,
                  shadowColor: AppColors.primary.withValues(alpha: 0.4),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
          );
        },
      ),
    );

    if (ok != true || !mounted) {
      numeroCtrl.dispose();
      observacaoCtrl.dispose();
      return;
    }
    final numeroOcorrencia = numeroCtrl.text.trim();
    final observacao = observacaoCtrl.text.trim();
    numeroCtrl.dispose();
    observacaoCtrl.dispose();

    final natureza = naturezaSelecionada;
    if (natureza == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecione a natureza.')),
        );
      }
      return;
    }
    final pontuacao = natureza.pontos;
    final created = await _ocorrenciasService.add(
      _userDocId,
      date: date,
      pontuacao: pontuacao,
      numeroOcorrencia: numeroOcorrencia,
      naturezaId: natureza.id,
      naturezaLabel: natureza.label,
      observacao: observacao,
    );
    if (anexoBytes != null &&
        anexoExtension != null &&
        anexoFileName != null &&
        anexoContentType != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enviando anexo...'), duration: Duration(seconds: 2)),
        );
      }
      Map<String, dynamic>? anexoPayload;
      try {
        anexoPayload = await _uploadAnexoOcorrencia(
          docId: created,
          bytes: anexoBytes!,
          extension: anexoExtension!,
          fileName: anexoFileName!,
          contentType: anexoContentType!,
        );
      } on _AnexoUploadException catch (err) {
        // Ocorrência já foi criada — não removemos para não perder dados;
        // o usuário pode reanexar pelo botão "clipe" na linha do card.
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text('Ocorrência salva, mas falhou o anexo: ${err.userMessage}\nReenvie pelo botão de clipe.'),
                backgroundColor: AppColors.error,
                duration: const Duration(seconds: 6),
              ),
            );
        }
        return;
      }
      try {
        await _ocorrenciasService.update(
          _userDocId,
          created,
          date: date,
          pontuacao: pontuacao,
          numeroOcorrencia: numeroOcorrencia,
          naturezaId: natureza.id,
          naturezaLabel: natureza.label,
          anexoUrl: (anexoPayload['anexoUrl'] ?? '').toString(),
          anexoFileName: (anexoPayload['anexoFileName'] ?? '').toString(),
          anexoContentType: (anexoPayload['anexoContentType'] ?? '').toString(),
          anexoSizeBytes: (anexoPayload['anexoSizeBytes'] as int?) ?? 0,
          anexoStoragePath: (anexoPayload['anexoStoragePath'] ?? '').toString(),
        );
      } catch (err) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text('Anexo enviado, mas falhou ao gravar no banco: $err'),
                backgroundColor: AppColors.error,
                duration: const Duration(seconds: 5),
              ),
            );
        }
        return;
      }
      if (mounted) {
        final isPdf = anexoExtension == 'pdf';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(isPdf
                  ? 'Ocorrência salva com PDF anexado.'
                  : 'Ocorrência salva com print anexado (otimizado).'),
            ),
          );
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ocorrência salva.')));
    }
  }

  Widget _buildLabelObrigatorio(String label) => Row(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
          const SizedBox(width: 4),
          Text('*', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w800)),
        ],
      );

  Widget _buildLabelOpcional(String label) => Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: AppColors.textPrimary,
        ),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.textMuted.withValues(alpha: 0.35)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.textMuted.withValues(alpha: 0.32)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accent, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
      );

  Widget _buildCampoDataForm(BuildContext ctx, DateTime date, void Function(DateTime) onDate) {
    return DateFieldWithCalendarOrManual(
      value: date,
      onChanged: onDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      label: 'Data da ocorrência',
    );
  }

  Future<OcorrenciaNatureza?> _dialogNovaNatureza(BuildContext context) async {
    String label = '';
    int pontos = 0;
    final labelCtrl = TextEditingController();
    final pontosCtrl = TextEditingController();
    return showDialog<OcorrenciaNatureza>(
      context: context,
      useSafeArea: true,
      builder: (ctx) {
        final fieldPad = KeyboardFormInsets.dialogFieldScrollPadding(
          ctx,
          footerEstimate: 100,
        );
        return wrapKeyboardAwareDialog(
          ctx,
          AlertDialog(
          scrollable: true,
          insetPadding: keyboardAwareDialogInsetPadding(ctx),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          titlePadding: EdgeInsets.zero,
          title: _dialogGradientTitle(
            icon: Icons.interests_rounded,
            title: 'Nova natureza',
            subtitle: 'Descrição e pontos usados nos lançamentos',
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          content: KeyboardAwareDialogScrollBody(
            maxHeightFactor: 0.5,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FastTextField(
                  controller: labelCtrl,
                  scrollPadding: fieldPad,
                  decoration: _inputDecoration('Descrição da natureza'),
                  onChanged: (v) => label = v.trim(),
                ),
                const SizedBox(height: 14),
                FastTextField(
                  controller: pontosCtrl,
                  keyboardType: TextInputType.number,
                  scrollPadding: fieldPad,
                  decoration: _inputDecoration('Pontuação (número inteiro)'),
                  onChanged: (v) => pontos = int.tryParse(v) ?? 0,
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            OutlinedButton.icon(
              onPressed: () => Navigator.of(ctx).pop(null),
              icon: Icon(Icons.close_rounded,
                  size: 18, color: AppColors.textSecondary.withValues(alpha: 0.95)),
              label: const Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w800)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: BorderSide(
                  color: AppColors.textMuted.withValues(alpha: 0.45),
                  width: 1.4,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                if (label.isEmpty) return;
                Navigator.of(ctx).pop(OcorrenciaNatureza(id: '', label: label, pontos: pontos));
              },
              icon: const Icon(Icons.add_circle_rounded, size: 20),
              label: const Text('Adicionar', style: TextStyle(fontWeight: FontWeight.w900)),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                elevation: 2,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
        );
      },
    ).whenComplete(() {
      labelCtrl.dispose();
      pontosCtrl.dispose();
    });
  }

  Future<void> _abrirEditarOcorrencia(BuildContext context, String docId, Map<String, dynamic> current) async {
    final jaTemFolgaInicial = current['folgaDate'] != null;
    DateTime date = (current['date'] is Timestamp) ? (current['date'] as Timestamp).toDate() : DateTime.now();
    String numeroOcorrencia = (current['numeroOcorrencia'] ?? '').toString();
    String observacao = (current['observacao'] ?? '').toString();
    final naturezaId = (current['naturezaId'] ?? '').toString();
    OcorrenciaNatureza? naturezaSelecionada = _naturezas.cast<OcorrenciaNatureza?>().firstWhere(
          (n) => n?.id == naturezaId,
          orElse: () => _naturezas.isNotEmpty ? _naturezas.first : null,
        );
    final numeroCtrl = TextEditingController(text: numeroOcorrencia);
    final observacaoCtrl = TextEditingController(text: observacao);
    final anexoAtualUrl = (current['anexoUrl'] ?? '').toString().trim();
    final anexoAtualNome = (current['anexoFileName'] ?? '').toString().trim();
    final anexoAtualPath = (current['anexoStoragePath'] ?? '').toString().trim();
    Uint8List? novoAnexoBytes;
    String? novoAnexoFileName;
    String? novoAnexoContentType;
    String? novoAnexoExtension;
    bool removerAnexo = false;

    final ok = await showDialog<bool>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final pontuacao = naturezaSelecionada?.pontos ?? 0;
          final fieldPad = KeyboardFormInsets.dialogFieldScrollPadding(
            ctx,
            footerEstimate: 140,
          );
          return wrapKeyboardAwareDialog(
            ctx,
            AlertDialog(
            scrollable: true,
            insetPadding: keyboardAwareDialogInsetPadding(ctx),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            titlePadding: EdgeInsets.zero,
            title: _dialogGradientTitle(
              icon: Icons.edit_calendar_rounded,
              title: 'Editar ocorrência',
              subtitle: jaTemFolgaInicial
                  ? 'Pode atualizar nº (RAI), observação e anexo. Data, natureza e folga ficam fixas.'
                  : 'Ajuste data, natureza ou número (RAI)',
            ),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            content: KeyboardAwareDialogScrollBody(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 280, maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (jaTemFolgaInicial) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.event_available_rounded, color: AppColors.success, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Esta ocorrência já foi baixada para folga em '
                                '${_formatDateAny(current['folgaDate'])}. '
                                'Data da ocorrência, natureza, RAI e folga permanecem fixos.',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () async {
                            final c = await showDialog<bool>(
                              context: ctx,
                              builder: (dCtx) => AlertDialog(
                                title: const Text('Limpar data da folga?'),
                                content: const Text(
                                  'O vínculo com esta data de folga será removido. '
                                  'Poderá marcar folga noutro dia quando reunir os pontos. '
                                  'O compromisso ligado no calendário de Escalas será atualizado.',
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancelar')),
                                  FilledButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Limpar')),
                                ],
                              ),
                            );
                            if (c == true && ctx.mounted) {
                              DateTime? diaFolga;
                              final fd0 = current['folgaDate'];
                              if (fd0 is Timestamp) {
                                final t = fd0.toDate();
                                diaFolga = DateTime(t.year, t.month, t.day);
                              }
                              await _ocorrenciasService.limparDatasFolga(_userDocId, [docId]);
                              if (diaFolga != null) {
                                await _syncCalendarioAposLimparFolga([diaFolga]);
                              }
                              if (ctx.mounted) Navigator.of(ctx).pop(false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Data da folga removida. Calendário de Escalas atualizado. Pode editar o lançamento novamente.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.event_busy_rounded, size: 20),
                          label: const Text('Limpar data da folga (cancelar vínculo)'),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    AbsorbPointer(
                      absorbing: jaTemFolgaInicial,
                      child: Opacity(
                        opacity: jaTemFolgaInicial ? 0.55 : 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildCampoDataForm(ctx, date, (d) => setDialogState(() => date = d)),
                            const SizedBox(height: 20),
                            _buildLabelObrigatorio('Natureza'),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<OcorrenciaNatureza>(
                              value: naturezaSelecionada,
                              isExpanded: true,
                              decoration: _inputDecoration('Selecione a natureza'),
                              items: _naturezas.map((n) => DropdownMenuItem(value: n, child: Text(n.label, overflow: TextOverflow.ellipsis, maxLines: 2))).toList(),
                              onChanged: (v) => setDialogState(() => naturezaSelecionada = v),
                            ),
                            if (naturezaSelecionada != null) ...[
                              const SizedBox(height: 8),
                              FilledButton.tonalIcon(
                                onPressed: () async {
                                  final idAntes = naturezaSelecionada!.id;
                                  await _dialogEditarNatureza(ctx, naturezaSelecionada!);
                                  await _carregarNaturezas();
                                  if (ctx.mounted) {
                                    final atualizada = _naturezas.where((n) => n.id == idAntes).firstOrNull ?? naturezaSelecionada;
                                    setDialogState(() => naturezaSelecionada = atualizada);
                                  }
                                },
                                icon: const Icon(Icons.tune_rounded, size: 18),
                                label: const Text('Editar natureza / pontuação'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.amber.withValues(alpha: 0.22),
                                  foregroundColor: AppColors.deepBlueDark,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            _buildLabelObrigatorio('Pontuação (somente leitura)'),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.star_rounded, color: AppColors.amber, size: 22),
                                  const SizedBox(width: 12),
                                  Text('${pontuacao} pts', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '(definido na natureza)',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      softWrap: true,
                                      maxLines: 3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildLabelObrigatorio('Número da ocorrência (RAI)'),
                    const SizedBox(height: 8),
                    FastTextField(
                      controller: numeroCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      scrollPadding: fieldPad,
                      decoration: _inputDecoration('Apenas números'),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    if (jaTemFolgaInicial) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Pode corrigir o número (RAI) caso tenha digitado errado.',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, height: 1.3),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _buildLabelOpcional('Observação'),
                    const SizedBox(height: 8),
                    FastTextField(
                      controller: observacaoCtrl,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      minLines: 2,
                      maxLines: 4,
                      scrollPadding: fieldPad,
                      decoration: _inputDecoration('Detalhes adicionais da ocorrência'),
                    ),
                    const SizedBox(height: 20),
                    _buildLabelOpcional('Anexo (PDF ou print)'),
                    const SizedBox(height: 8),
                    if (anexoAtualUrl.isNotEmpty && novoAnexoBytes == null && !removerAnexo)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => mostrarAnexoNaMesmaTela(
                            ctx,
                            url: anexoAtualUrl,
                            fileName: anexoAtualNome.isEmpty ? 'Anexo ocorrência' : anexoAtualNome,
                          ),
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: const Text('Ver anexo atual'),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await _pickAnexoOcorrencia(ctx);
                              if (picked == null) return;
                              setDialogState(() {
                                novoAnexoBytes = picked.bytes;
                                novoAnexoFileName = picked.fileName;
                                novoAnexoContentType = picked.contentType;
                                novoAnexoExtension = picked.extension;
                                removerAnexo = false;
                              });
                            },
                            icon: const Icon(Icons.attach_file_rounded, size: 18),
                            label: Text(
                              anexoAtualUrl.isNotEmpty || novoAnexoBytes != null ? 'Trocar anexo' : 'Anexar arquivo',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        if (anexoAtualUrl.isNotEmpty || novoAnexoBytes != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => setDialogState(() {
                              removerAnexo = true;
                              novoAnexoBytes = null;
                              novoAnexoFileName = null;
                              novoAnexoContentType = null;
                              novoAnexoExtension = null;
                            }),
                            icon: const Icon(Icons.delete_outline_rounded),
                            tooltip: 'Remover anexo',
                          ),
                        ],
                      ],
                    ),
                    if (novoAnexoFileName != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '$novoAnexoFileName (${((novoAnexoBytes?.length ?? 0) / 1024).toStringAsFixed(0)} KB)',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (jaTemFolgaInicial) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Pode anexar o PDF / print mesmo após pegar a folga (não altera os pontos já usados).',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, height: 1.3),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actions: [
              OutlinedButton.icon(
                onPressed: () => Navigator.of(ctx).pop(false),
                icon: Icon(Icons.close_rounded,
                    size: 18, color: AppColors.textSecondary.withValues(alpha: 0.95)),
                label: const Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w800)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: BorderSide(
                    color: AppColors.textMuted.withValues(alpha: 0.45),
                    width: 1.4,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () {
                  if (!jaTemFolgaInicial && naturezaSelecionada == null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Selecione a natureza.')));
                    return;
                  }
                  if (numeroCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Informe o número da ocorrência (RAI).')));
                    return;
                  }
                  Navigator.of(ctx).pop(true);
                },
                icon: const Icon(Icons.save_rounded, size: 20),
                label: const Text('Guardar alterações', style: TextStyle(fontWeight: FontWeight.w900)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shadowColor: AppColors.accent.withValues(alpha: 0.45),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
          );
        },
      ),
    );

    if (ok != true || !mounted || (!jaTemFolgaInicial && naturezaSelecionada == null)) {
      numeroCtrl.dispose();
      observacaoCtrl.dispose();
      return;
    }
    numeroOcorrencia = numeroCtrl.text.trim();
    observacao = observacaoCtrl.text.trim();
    final natureza = naturezaSelecionada;
    if (!jaTemFolgaInicial && natureza == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecione a natureza.')),
        );
      }
      return;
    }
    final pontuacao = natureza?.pontos ?? ((current['pontuacao'] as int?) ?? 0);
    numeroCtrl.dispose();
    observacaoCtrl.dispose();
    final dateLocked =
        (current['date'] is Timestamp) ? (current['date'] as Timestamp).toDate() : date;
    final pontLocked = (current['pontuacao'] as int?) ?? pontuacao;
    final natIdLocked = (current['naturezaId'] ?? '').toString();
    final natLabelLocked = (current['naturezaLabel'] ?? '').toString();

    final dateFinal = jaTemFolgaInicial ? dateLocked : date;
    final pontuacaoFinal = jaTemFolgaInicial ? pontLocked : pontuacao;
    final naturezaIdFinal = jaTemFolgaInicial ? natIdLocked : (natureza?.id ?? '');
    final naturezaLabelFinal = jaTemFolgaInicial ? natLabelLocked : (natureza?.label ?? '');

    await _ocorrenciasService.update(
      _userDocId,
      docId,
      date: dateFinal,
      pontuacao: pontuacaoFinal,
      numeroOcorrencia: numeroOcorrencia,
      naturezaId: naturezaIdFinal,
      naturezaLabel: naturezaLabelFinal,
      observacao: observacao,
    );

    if (removerAnexo && anexoAtualPath.isNotEmpty) {
      try {
        await FirebaseStorage.instance.ref(anexoAtualPath).delete();
      } catch (_) {}
      try {
        await _ocorrenciasService.update(
          _userDocId,
          docId,
          date: dateFinal,
          pontuacao: pontuacaoFinal,
          numeroOcorrencia: numeroOcorrencia,
          naturezaId: naturezaIdFinal,
          naturezaLabel: naturezaLabelFinal,
          observacao: observacao,
          limparAnexo: true,
        );
      } catch (err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Não foi possível remover o anexo: $err'),
              backgroundColor: AppColors.error,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }
    } else if (novoAnexoBytes != null &&
        novoAnexoExtension != null &&
        novoAnexoFileName != null &&
        novoAnexoContentType != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enviando novo anexo...'), duration: Duration(seconds: 2)),
        );
      }
      Map<String, dynamic>? anexoPayload;
      try {
        anexoPayload = await _uploadAnexoOcorrencia(
          docId: docId,
          bytes: novoAnexoBytes!,
          extension: novoAnexoExtension!,
          fileName: novoAnexoFileName!,
          contentType: novoAnexoContentType!,
        );
      } on _AnexoUploadException catch (err) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text('Ocorrência atualizada, mas o novo anexo falhou: ${err.userMessage}'),
                backgroundColor: AppColors.error,
                duration: const Duration(seconds: 6),
              ),
            );
        }
        return;
      }
      // Só apaga o anexo antigo depois que o novo subiu (defensivo).
      final newPath = (anexoPayload['anexoStoragePath'] ?? '').toString().trim();
      if (anexoAtualPath.isNotEmpty && anexoAtualPath != newPath) {
        try {
          await FirebaseStorage.instance.ref(anexoAtualPath).delete();
        } catch (_) {}
      }
      try {
        await _ocorrenciasService.update(
          _userDocId,
          docId,
          date: dateFinal,
          pontuacao: pontuacaoFinal,
          numeroOcorrencia: numeroOcorrencia,
          naturezaId: naturezaIdFinal,
          naturezaLabel: naturezaLabelFinal,
          observacao: observacao,
          anexoUrl: (anexoPayload['anexoUrl'] ?? '').toString(),
          anexoFileName: (anexoPayload['anexoFileName'] ?? '').toString(),
          anexoContentType: (anexoPayload['anexoContentType'] ?? '').toString(),
          anexoSizeBytes: (anexoPayload['anexoSizeBytes'] as int?) ?? 0,
          anexoStoragePath: (anexoPayload['anexoStoragePath'] ?? '').toString(),
        );
      } catch (err) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text('Anexo enviado, mas falhou ao salvar no banco: $err'),
                backgroundColor: AppColors.error,
                duration: const Duration(seconds: 5),
              ),
            );
        }
        return;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Ocorrência atualizada.')));
    }
  }

  Future<void> _confirmarRemover(String docId, Map<String, dynamic> e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.error.withValues(alpha: 0.9), size: 28),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Remover ocorrência?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        content: Text(
          '${_formatDate(e['date'])} — ${e['naturezaLabel']} (${e['pontuacao']} pts). Esta ação não pode ser desfeita.',
          style: const TextStyle(
            fontSize: 14,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton.icon(
            onPressed: () => Navigator.of(ctx).pop(false),
            icon: Icon(Icons.close_rounded,
                size: 18, color: AppColors.textSecondary.withValues(alpha: 0.95)),
            label: const Text('Manter', style: TextStyle(fontWeight: FontWeight.w800)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: BorderSide(
                color: AppColors.textMuted.withValues(alpha: 0.45),
                width: 1.4,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.delete_forever_rounded, size: 20),
            label: const Text('Remover', style: TextStyle(fontWeight: FontWeight.w900)),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              elevation: 2,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final anexoPath = (e['anexoStoragePath'] ?? '').toString().trim();
    if (anexoPath.isNotEmpty) {
      try {
        await FirebaseStorage.instance.ref(anexoPath).delete();
      } catch (_) {}
    }
    await _ocorrenciasService.delete(_userDocId, docId);
    if (mounted) {
      setState(() => _selecionadosFolga.remove(docId));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ocorrência removida.')));
    }
  }

  Future<void> _abrirGerenciarNaturezas(BuildContext context) async {
    await _carregarNaturezas();
    if (!mounted) return;
    String filtroNome = '';
    final filtroCtrl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> refreshLocal() async {
            await _carregarNaturezas();
            if (!mounted) return;
            setState(() {});
            setSheetState(() {});
          }

          final items = List<OcorrenciaNatureza>.from(_naturezas)
            ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
          final filtro = filtroNome.trim().toLowerCase();
          final itensFiltrados = filtro.isEmpty
              ? items
              : items.where((n) => n.label.toLowerCase().contains(filtro)).toList();

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                _dialogGradientTitle(
                  icon: Icons.interests_rounded,
                  title: 'Editar/Adicionar naturezas',
                  subtitle: 'Inclusão, edição e exclusão no mesmo painel',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: const Text(
                            'Voltar',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: BorderSide(
                              color:
                                  AppColors.primary.withValues(alpha: 0.45),
                              width: 1.4,
                            ),
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text(
                            'Cancelar',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                AppColors.error.withValues(alpha: 0.12),
                            foregroundColor: AppColors.error,
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.accent.withValues(alpha: 0.45), width: 1.5),
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.add_circle_rounded, color: AppColors.accent),
                          title: const Text(
                            'Adicionar natureza',
                            style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                          ),
                          subtitle: const Text('Cria uma nova opção para usar nas ocorrências'),
                          onTap: () async {
                            final nova = await _dialogNovaNatureza(context);
                            if (nova != null) {
                              await _naturezasService.add(_userDocId, nova.label, nova.pontos);
                              await refreshLocal();
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      FastTextField(
                        controller: filtroCtrl,
                        kind: FastTextFieldKind.search,
                        decoration: _inputDecoration('Buscar natureza por nome').copyWith(
                          prefixIcon: const Icon(Icons.search_rounded),
                          hintText: 'Digite para filtrar',
                        ),
                        onChanged: (v) => setSheetState(() => filtroNome = v),
                      ),
                      const SizedBox(height: 10),
                      if (filtro.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${itensFiltrados.length} resultado(s) para "$filtroNome"',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      if (filtro.isNotEmpty && itensFiltrados.isEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.textMuted.withValues(alpha: 0.35),
                            ),
                          ),
                          child: const Text(
                            'Nenhuma natureza encontrada para o filtro informado.',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ...itensFiltrados.map((n) {
                        final parsed = int.tryParse(n.id);
                        final isPadrao = parsed != null && parsed >= 1 && parsed <= 7;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            tileColor: const Color(0xFFF8FAFC),
                            title: Text(n.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              '${n.pontos} pontos',
                              style: TextStyle(
                                color: AppColors.accent.withValues(alpha: 0.95),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            trailing: Wrap(
                              spacing: 6,
                              children: [
                                FilledButton.tonal(
                                  onPressed: () async {
                                    await _dialogEditarNatureza(context, n);
                                    await refreshLocal();
                                  },
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(40, 40),
                                    padding: EdgeInsets.zero,
                                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                                    foregroundColor: AppColors.primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Icon(Icons.edit_outlined, size: 20),
                                ),
                                if (!isPadrao)
                                  FilledButton.tonal(
                                    onPressed: () async {
                                      final ok = await _confirmarExcluirNatureza(context, n);
                                      if (ok != true) return;
                                      await _naturezasService.remove(_userDocId, n.id);
                                      await refreshLocal();
                                    },
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size(40, 40),
                                      padding: EdgeInsets.zero,
                                      backgroundColor: AppColors.error.withValues(alpha: 0.12),
                                      foregroundColor: AppColors.error,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Icon(Icons.delete_outline_rounded, size: 20),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.check_rounded, size: 20),
                    label: const Text('Concluído', style: TextStyle(fontWeight: FontWeight.w900)),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(filtroCtrl.dispose);
  }

  Future<bool?> _confirmarExcluirNatureza(BuildContext context, OcorrenciaNatureza n) async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Excluir natureza?'),
        content: Text(
          'A natureza "${n.label}" será removida. Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  Future<void> _dialogEditarNatureza(BuildContext context, OcorrenciaNatureza n) async {
    String label = n.label;
    int pontos = n.pontos;
    final labelCtrl = TextEditingController(text: label);
    final pontosCtrl = TextEditingController(text: pontos.toString());
    final ok = await showDialog<bool>(
      context: context,
      useSafeArea: true,
      builder: (ctx) {
        final fieldPad = KeyboardFormInsets.dialogFieldScrollPadding(
          ctx,
          footerEstimate: 100,
        );
        return wrapKeyboardAwareDialog(
          ctx,
          AlertDialog(
          scrollable: true,
          insetPadding: keyboardAwareDialogInsetPadding(ctx),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          titlePadding: EdgeInsets.zero,
          title: _dialogGradientTitle(
            icon: Icons.tune_rounded,
            title: 'Editar natureza',
            subtitle: 'Altera rótulo e pontuação em todos os usos futuros',
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          content: KeyboardAwareDialogScrollBody(
            maxHeightFactor: 0.5,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FastTextField(
                  decoration: _inputDecoration('Descrição'),
                  controller: labelCtrl,
                  scrollPadding: fieldPad,
                  onChanged: (v) => label = v.trim(),
                ),
                const SizedBox(height: 14),
                FastTextField(
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration('Pontuação'),
                  controller: pontosCtrl,
                  scrollPadding: fieldPad,
                  onChanged: (v) => pontos = int.tryParse(v) ?? 0,
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            OutlinedButton.icon(
              onPressed: () => Navigator.of(ctx).pop(false),
              icon: Icon(Icons.close_rounded,
                  size: 18, color: AppColors.textSecondary.withValues(alpha: 0.95)),
              label: const Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w800)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: BorderSide(
                  color: AppColors.textMuted.withValues(alpha: 0.45),
                  width: 1.4,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.save_rounded, size: 20),
              label: const Text('Salvar', style: TextStyle(fontWeight: FontWeight.w900)),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 2,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
        );
      },
    ).whenComplete(() {
      labelCtrl.dispose();
      pontosCtrl.dispose();
    });
    if (ok == true && label.isNotEmpty) {
      await _naturezasService.update(_userDocId, OcorrenciaNatureza(id: n.id, label: label, pontos: pontos));
      await _carregarNaturezas();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Natureza atualizada.')));
      }
    }
  }
}

/// Tile expansível para exibir observação extra em lançamentos (ex.: restantes da folga).
class _ObservacaoExpansivel extends StatefulWidget {
  final String texto;

  const _ObservacaoExpansivel({required this.texto});

  @override
  State<_ObservacaoExpansivel> createState() => _ObservacaoExpansivelState();
}

class _ObservacaoExpansivelState extends State<_ObservacaoExpansivel> {
  bool _expandido = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expandido = !_expandido),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    _expandido ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _expandido ? 'Ocultar observação' : 'Ver observação completa',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expandido)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.deepBlueDark.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.deepBlueDark.withValues(alpha: 0.15)),
              ),
              child: SelectableText(
                widget.texto,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Erro amigável para falhas de upload de anexo (PDF/print) no módulo Produtividade.
/// Mensagem já vem traduzida para PT-BR e pronta para exibir em SnackBar.
class _AnexoUploadException implements Exception {
  final String userMessage;
  _AnexoUploadException(this.userMessage);
  @override
  String toString() => userMessage;
}

/// Compressão JPEG em isolate (compute) — não trava a UI no Android.
/// Alvo ~700KB, largura máx 1600px, qualidades agressivas para ficar leve e rápido.
Uint8List? _compressImageInIsolate(Uint8List source) {
  const int targetBytes = 700 * 1024;
  final decoded = img.decodeImage(source);
  if (decoded == null) return null;
  final resized = decoded.width > 1600
      ? img.copyResize(decoded, width: 1600, interpolation: img.Interpolation.average)
      : decoded;
  const qualities = [78, 70, 62, 55, 48];
  Uint8List? best;
  for (final q in qualities) {
    final out = Uint8List.fromList(img.encodeJpg(resized, quality: q));
    best = out;
    if (out.length <= targetBytes) break;
  }
  return best;
}
