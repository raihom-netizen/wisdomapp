import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:flutter/material.dart' hide showDatePicker;
import '../widgets/fast_text_field.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../models/note_entry.dart';
import '../models/user_profile.dart';
import '../services/notes_service.dart';
import '../constants/link_utils_icons.dart';
import '../services/link_utils_preference_service.dart';
import '../theme/app_colors.dart';
import '../theme/gemini_theme.dart';
import '../utils/premium_upgrade.dart';
import '../utils/url_launcher_helper.dart';
import 'link_utils_editor_screen.dart';
import '../utils/date_picker_a11y.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/home_shell_layout.dart';
/// Verde do ícone editar (padrão lista tipo Gestão Yahweh / fornecedor).
const Color _yahwehEditGreen = Color(0xFF16A34A);

/// Cores da categoria no editor (4 opções). O cartão na lista usa barra azul fixa.
const List<Color> _noteCategoryColors = [
  Color(0xFF22C55E),
  Color(0xFFF97316),
  Color(0xFF2563EB),
  Color(0xFF8B5CF6),
];

/// Gradiente do fundo da tela Minhas Anotações (céu → branco).
const LinearGradient _anotacoesBodyGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0xFFDBEAFE),
    Color(0xFFF0F9FF),
    Color(0xFFF8FAFC),
    Colors.white,
  ],
  stops: [0.0, 0.2, 0.45, 1.0],
);

/// Gradiente dos campos de pesquisa (mesma família cromática da aba / corpo).
const LinearGradient _anotacoesSearchFieldGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color(0xFFDBEAFE),
    Color(0xFFE0F2FE),
    Color(0xFFF0F9FF),
    Color(0xFFFFFFFF),
  ],
  stops: [0.0, 0.3, 0.65, 1.0],
);

/// Botão Voltar (ícone + texto) para iPhone — todas as telas do módulo Minhas Anotações.
Widget _buildVoltarButtonAnotacoes(BuildContext context) {
  final color = Theme.of(context).appBarTheme.foregroundColor ?? Theme.of(context).colorScheme.onSurface;
  return Semantics(
    label: 'Voltar',
    button: true,
    child: InkWell(
      onTap: () => Navigator.of(context).pop(),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back_rounded, size: 24, color: color),
            const SizedBox(width: 6),
            Text('Voltar', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: color)),
          ],
        ),
      ),
    ),
  );
}

class AnotacoesScreen extends StatefulWidget {
  final String uid;
  final UserProfile profile;
  final void Function(int index)? onNavigateTo;

  const AnotacoesScreen({
    super.key,
    required this.uid,
    required this.profile,
    this.onNavigateTo,
  });

  @override
  State<AnotacoesScreen> createState() => _AnotacoesScreenState();
}

enum _NoteSort { recent, oldest, titleAz }

class _AnotacoesScreenState extends State<AnotacoesScreen> with SingleTickerProviderStateMixin {
  String get _dataUid => firestoreUserDocIdForAppShell(widget.uid);
  late TabController _tabController;
  final NotesService _notesService = NotesService();
  /// Streams em [NotesService]/[LinkUtilsPreferenceService] usam `asBroadcastStream` após o map.
  late Stream<List<NoteEntry>> _notesStream;
  late Stream<List<LinkUtilItem>> _linksStream;
  StreamSubscription<fa.User?>? _authStateSub;
  final TextEditingController _noteSearchCtrl = TextEditingController();
  final TextEditingController _linkSearchCtrl = TextEditingController();
  _NoteSort _noteSort = _NoteSort.recent;
  String _noteSearchQuery = '';
  String _linkSearchQuery = '';
  Timer? _noteSearchDebounceTimer;
  Timer? _linkSearchDebounceTimer;

  void _bindDataStreams() {
    _notesStream = _notesService.streamNotes(_dataUid);
    _linksStream = LinkUtilsPreferenceService().stream(_dataUid);
  }

  /// Recria as streams (útil após limpar cache do Firestore ou falha intermitente).
  Future<void> _clearFirestoreCacheAndRetry() async {
    try {
      if (!mounted) return;
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
      _bindDataStreams();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cache limpo. Recarregando anotações…')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível limpar o cache: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _bindDataStreams();
    _authStateSub = fa.FirebaseAuth.instance.authStateChanges().listen((_) {
      if (!mounted) return;
      _bindDataStreams();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _authStateSub?.cancel();
    _noteSearchDebounceTimer?.cancel();
    _linkSearchDebounceTimer?.cancel();
    _tabController.dispose();
    _noteSearchCtrl.dispose();
    _linkSearchCtrl.dispose();
    super.dispose();
  }

  /// Campo de busca com o mesmo gradiente / paleta do corpo da aba (premium Yahweh).
  Widget _buildYahwehSearchField({
    required TextEditingController controller,
    required String hintText,
    required ValueChanged<String> onChanged,
    bool dense = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlueDark.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            gradient: _anotacoesSearchFieldGradient,
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.24),
              width: 1,
            ),
          ),
          child: FastTextField(
            controller: controller,
            style: TextStyle(
              fontSize: dense ? 14.5 : 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              height: 1.25,
            ),
            cursorColor: AppColors.primary,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(
                color: AppColors.textPrimary.withValues(alpha: 0.42),
                fontSize: dense ? 14 : 14.5,
                fontWeight: FontWeight.w500,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 10, right: 6),
                child: Align(
                  widthFactor: 1,
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.58),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                    ),
                    child: Icon(
                      Icons.search_rounded,
                      size: 22,
                      color: AppColors.deepBlueDark.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
              filled: true,
              fillColor: Colors.transparent,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.55),
                  width: 1.5,
                ),
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 12 : 14),
              isDense: dense,
            ),
            textCapitalization: TextCapitalization.none,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  Future<void> _togglePin(NoteEntry note) async {
    if (!widget.profile.hasActiveLicense) return;
    await _notesService.update(_dataUid, note.copyWith(isPinned: !note.isPinned));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(note.isPinned ? 'Anotação desfixada.' : 'Anotação fixada no topo.')),
      );
    }
  }

  String _noteAsPlainText(NoteEntry note) {
    final lines = <String>[note.title, DateFormat('dd/MM/yyyy').format(note.date), ''];
    for (final item in note.items) {
      lines.add('• $item');
    }
    return lines.join('\n');
  }

  /// [anchorContext] = contexto do botão/card (obrigatório para [sharePositionOrigin] em iPad e alguns Android).
  Future<void> _shareNote(BuildContext anchorContext, NoteEntry note) async {
    final text = _noteAsPlainText(note);
    if (text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nada para compartilhar.')),
        );
      }
      return;
    }
    final subjectRaw = note.title.trim().isEmpty ? 'Minha anotação' : note.title.trim();
    final subject = subjectRaw.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();

    // Windows (implementação do plugin): costuma abrir mailto: e falhar sem cliente de e-mail — preferir cópia direta.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Texto copiado. Cole onde quiser (Ctrl+V) — no Windows o “compartilhar” usa a área de transferência.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    Rect? origin;
    final ro = anchorContext.findRenderObject();
    if (ro is RenderBox && ro.hasSize) {
      origin = ro.localToGlobal(Offset.zero) & ro.size;
    } else {
      final sz = MediaQuery.sizeOf(anchorContext);
      final pad = MediaQuery.paddingOf(anchorContext);
      origin = Rect.fromCenter(
        center: Offset(sz.width / 2, pad.top + sz.height / 3),
        width: 2,
        height: 2,
      );
    }

    Future<void> tryClipboardFallback() async {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb
                ? 'Compartilhamento nativo indisponível. Texto copiado — cole onde quiser.'
                : 'Não foi possível abrir o compartilhamento. Texto copiado para a área de transferência.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    try {
      await Share.share(
        text,
        subject: subject,
        sharePositionOrigin: origin,
      );
    } catch (e, st) {
      debugPrint('Share.share failed: $e\n$st');
      if (!mounted) return;
      try {
        await Share.share(
          text,
          sharePositionOrigin: origin,
        );
      } catch (e2, st2) {
        debugPrint('Share.share (sem subject) failed: $e2\n$st2');
        if (!mounted) return;
        try {
          await tryClipboardFallback();
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Não foi possível compartilhar. Tente copiar o texto manualmente.'),
                backgroundColor: AppColors.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _copyNote(NoteEntry note) async {
    await Clipboard.setData(ClipboardData(text: _noteAsPlainText(note)));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anotação copiada para a área de transferência.')),
      );
    }
  }

  void _addNote() {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    _showNoteForm(context, uid: _dataUid);
  }

  void _editNote(NoteEntry note) {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    _showNoteForm(context, uid: _dataUid, existing: note);
  }

  Future<void> _deleteNote(NoteEntry note) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir anotação'),
        content: Text('Excluir "${note.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await _notesService.delete(_dataUid, note.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Anotação excluída.')));
      }
    }
  }

  Widget _buildPremiumAddNoteButton() {
    return Semantics(
      label: 'Adicionar nova anotação',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: _addNote,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF22C55E), AppColors.success, Color(0xFF15803D)],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              boxShadow: [
                BoxShadow(color: AppColors.deepBlueDark.withValues(alpha: 0.2), blurRadius: 18, offset: const Offset(0, 8)),
                BoxShadow(color: const Color(0xFF15803D).withValues(alpha: 0.28), blurRadius: 12, offset: const Offset(0, 4)),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.note_add_rounded, color: Colors.white, size: 26),
                  const SizedBox(width: 10),
                  const Text(
                    'Adicionar Nova Anotação',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _showNoteForm(
    BuildContext context, {
    required String uid,
    NoteEntry? existing,
  }) async {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final itemsCtrl = TextEditingController(text: (existing?.items ?? []).join('\n'));

    // Tela full-screen (antes era bottom sheet) para iOS/Android/Web instalável:
    // o usuário enxerga o título, a data, a cor e os itens sem rolar quando o
    // teclado abre.
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => _NoteFormSheet(
          uid: uid,
          existing: existing,
          titleCtrl: titleCtrl,
          itemsCtrl: itemsCtrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: _anotacoesBodyGradient,
      ),
      child: StreamBuilder<List<NoteEntry>>(
        stream: _notesStream,
        builder: (context, notesSnap) {
          return StreamBuilder<List<LinkUtilItem>>(
            stream: _linksStream,
            builder: (context, linksSnap) {
              final noteCount = notesSnap.data?.length;
              final linkItems = linksSnap.hasData && linksSnap.data!.isNotEmpty
                  ? linksSnap.data!
                  : LinkUtilsPreferenceService.defaultList();
              final linkCount = linkItems.length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildYahwehTopBar(context, noteCount, linkCount),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildAnotacoesTabBody(notesSnap),
                        _buildLinksFavoritosTabBody(linksSnap),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// Abas Anotações | Links + atualizar — título e voltar ficam na faixa azul do [HomeShell].
  Widget _buildYahwehTopBar(BuildContext context, int? noteCount, int linkCount) {
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TabBar(
                controller: _tabController,
                indicatorColor: AppColors.primary,
                indicatorWeight: 3,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textMuted,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                tabs: [
                  Tab(text: noteCount == null ? 'Anotações' : 'Anotações ($noteCount)'),
                  Tab(text: 'Links ($linkCount)'),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.refresh_rounded, color: AppColors.primary.withValues(alpha: 0.9)),
              tooltip: 'Atualizar',
              onPressed: () {
                _bindDataStreams();
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Título + subtítulo da lista (padrão fornecedor / Yahweh: ícone quadrado + texto).
  Widget _buildNotesSectionHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Icon(Icons.view_list_rounded, color: AppColors.primary, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Suas anotações',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppColors.textPrimary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Toque num cartão para editar ou use os ícones • ordenado por ${_noteSortLabel()}',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _noteSortLabel() {
    switch (_noteSort) {
      case _NoteSort.recent:
        return 'data (mais recente primeiro)';
      case _NoteSort.oldest:
        return 'data (mais antiga primeiro)';
      case _NoteSort.titleAz:
        return 'título (A–Z)';
    }
  }

  Widget _buildLinksSectionHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Icon(Icons.link_rounded, color: AppColors.primary, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Links e favoritos',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppColors.textPrimary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Toque num cartão para abrir no navegador • favoritos aparecem primeiro',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Conteúdo da aba de notas — usa o [AsyncSnapshot] do **único** [StreamBuilder] de notas (não subscrever de novo).
  Widget _buildAnotacoesTabBody(AsyncSnapshot<List<NoteEntry>> snapshot) {
    if (snapshot.hasError) {
      if (kDebugMode) {
        debugPrint('[Minhas Anotações] stream error: ${snapshot.error}');
      }
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 48, color: Colors.orange.shade700),
              const SizedBox(height: 12),
              Text(
                'Não foi possível carregar as anotações. Verifique a sessão e a rede.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                  childrenPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  title: const Text(
                    'Mostrar detalhe técnico (para o suporte)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  children: [
                    SelectableText(
                      snapshot.error?.toString() ?? 'erro desconhecido',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
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
                    onPressed: () {
                      _bindDataStreams();
                      setState(() {});
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Tentar novamente'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _clearFirestoreCacheAndRetry,
                    icon: const Icon(Icons.cleaning_services_rounded),
                    label: const Text('Limpar cache local e tentar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 16),
              Text(
                'Carregando anotações…',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }
    var notes = snapshot.data ?? [];
    if (_noteSearchQuery.isNotEmpty) {
      notes = notes.where((n) {
        if (n.title.toLowerCase().contains(_noteSearchQuery)) return true;
        for (final item in n.items) {
          if (item.toLowerCase().contains(_noteSearchQuery)) return true;
        }
        return false;
      }).toList();
    }
    notes = List.from(notes)
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        switch (_noteSort) {
          case _NoteSort.recent:
            return (b.updatedAt ?? b.date).compareTo(a.updatedAt ?? a.date);
          case _NoteSort.oldest:
            return (a.updatedAt ?? a.date).compareTo(b.updatedAt ?? b.date);
          case _NoteSort.titleAz:
            return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        }
      });

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        homeShellScrollBottomPadding(
          context,
          embeddedInHomeShell: widget.onNavigateTo != null,
          tail: 12,
        ),
      ),
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildNotesSectionHeader(),
          const SizedBox(height: 14),
          _buildPremiumAddNoteButton(),
          const SizedBox(height: 16),
          _buildYahwehSearchField(
            controller: _noteSearchCtrl,
            hintText: 'Buscar por título ou texto...',
            dense: true,
            onChanged: (v) {
              _noteSearchDebounceTimer?.cancel();
              _noteSearchDebounceTimer =
                  Timer(const Duration(milliseconds: 320), () {
                if (!mounted) return;
                setState(() => _noteSearchQuery = v.trim().toLowerCase());
              });
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.sort_rounded, size: 20, color: AppColors.primary.withValues(alpha: 0.9)),
                ),
                const SizedBox(width: 10),
                Text('Ordenar:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<_NoteSort>(
                      value: _noteSort,
                      isExpanded: true,
                      isDense: true,
                      borderRadius: BorderRadius.circular(12),
                      icon: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primary.withValues(alpha: 0.85)),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary),
                      items: const [
                        DropdownMenuItem(value: _NoteSort.recent, child: Text('Mais recentes')),
                        DropdownMenuItem(value: _NoteSort.oldest, child: Text('Mais antigas')),
                        DropdownMenuItem(value: _NoteSort.titleAz, child: Text('Título A–Z')),
                      ],
                      onChanged: (v) => setState(() => _noteSort = v ?? _NoteSort.recent),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (notes.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Center(
                child: Text(
                  _noteSearchQuery.isEmpty
                      ? 'Nenhuma anotação. Toque em "Adicionar Nova Anotação" para criar.'
                      : 'Nenhuma anotação encontrada para a busca.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: GeminiTheme.textMuted, fontSize: 14, height: 1.4),
                ),
              ),
            )
          else
            ..._noteCardWidgets(notes),
        ],
      ),
    );
  }

  /// Lista explícita — evita `ListView` dentro de scroll (layout desktop).
  List<Widget> _noteCardWidgets(List<NoteEntry> notes) {
    final w = <Widget>[];
    for (var i = 0; i < notes.length; i++) {
      if (i > 0) w.add(const SizedBox(height: 16));
      final note = notes[i];
      w.add(
        _NoteCard(
          key: ValueKey<String>(note.id),
          note: note,
          onEdit: () => _editNote(note),
          onDelete: () => _deleteNote(note),
          onPin: () => _togglePin(note),
          onShare: (ctx) => unawaited(_shareNote(ctx, note)),
          onCopy: () => _copyNote(note),
          canEdit: widget.profile.hasActiveLicense,
        ),
      );
    }
    return w;
  }

  /// Uma subscrição de [LinkUtilsPreferenceService.stream] no `build` — não duplicar com outro [StreamBuilder].
  Widget _buildLinksFavoritosTabBody(AsyncSnapshot<List<LinkUtilItem>> snapshot) {
    if (snapshot.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Não foi possível carregar os links.\n${snapshot.error}',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.error, fontSize: 14, height: 1.4),
          ),
        ),
      );
    }
    if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final rawItems = snapshot.hasData ? snapshot.data! : <LinkUtilItem>[];
    final items = rawItems.isEmpty
        ? LinkUtilsPreferenceService.defaultList()
        : rawItems;
    var filtered = items;
    if (_linkSearchQuery.isNotEmpty) {
      final searchLower = _linkSearchQuery.toLowerCase();
      filtered = items.where((link) {
        final titulo = link.title.toLowerCase();
        final url = link.url.toLowerCase();
        final desc = link.description.toLowerCase();
        return titulo.contains(searchLower) ||
            url.contains(searchLower) ||
            desc.contains(searchLower);
      }).toList();
    }
    filtered = List.from(filtered)
      ..sort((a, b) {
        if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    final links = filtered.map((item) => _linkUtilFromItem(item)).toList();
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        homeShellScrollBottomPadding(
          context,
          embeddedInHomeShell: widget.onNavigateTo != null,
          tail: 12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLinksSectionHeader(),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LinkUtilsEditorScreen(
                      uid: _dataUid,
                      initialItems: List.from(items),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.tune_rounded, size: 20),
              label: const Text('Personalizar lista'),
              style: FilledButton.styleFrom(
                foregroundColor: AppColors.primary,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildYahwehSearchField(
            controller: _linkSearchCtrl,
            hintText: 'Pesquisar links...',
            dense: false,
            onChanged: (v) {
              _linkSearchDebounceTimer?.cancel();
              _linkSearchDebounceTimer =
                  Timer(const Duration(milliseconds: 320), () {
                if (!mounted) return;
                setState(() => _linkSearchQuery = v.trim().toLowerCase());
              });
            },
          ),
          const SizedBox(height: 16),
          if (links.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Center(
                child: Column(
                  children: [
                    Text(
                      _linkSearchQuery.isEmpty
                          ? 'Nenhum link. Toque em "Personalizar" para incluir.'
                          : 'Nenhum link encontrado para a busca.',
                      style: TextStyle(color: GeminiTheme.textMuted, fontSize: 14, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => LinkUtilsEditorScreen(
                              uid: _dataUid,
                              initialItems: List.from(LinkUtilsPreferenceService.defaultList()),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Abrir personalização'),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: links.map((link) => _LinkUtilCard(link: link)).toList(),
            ),
        ],
      ),
    );
  }

  /// Converte item salvo em _LinkUtil. Ícone sempre da lista do app (evita IconData codePoint que falha na web).
  static _LinkUtil _linkUtilFromItem(LinkUtilItem item) {
    final icon = linkUtilIconForDisplay(
      codePoint: item.iconCodePoint,
      index: item.iconIndex,
    );
    final iconColor = linkUtilColorForDisplay(
      colorValue: item.iconColorValue,
      index: item.iconIndex,
    );
    final subLinks = item.subLinks.isEmpty
        ? null
        : item.subLinks.map((s) => _SubLink(title: s.title, url: s.url)).toList();
    return _LinkUtil(
      title: item.title,
      description: item.description,
      url: item.url,
      icon: icon,
      iconColor: iconColor,
      subLinks: subLinks,
      isFavorite: item.isFavorite,
    );
  }
}

/// Sub-item de link (ex.: estado com sua URL).
class _SubLink {
  final String title;
  final String url;

  const _SubLink({required this.title, required this.url});
}

/// Item de link útil: título, descrição, URL, ícone, cor (persistidos como codePoint/value no banco) e opcionalmente sublinks.
class _LinkUtil {
  final String title;
  final String description;
  final String url;
  final IconData icon;
  /// Cor do ícone (do banco iconColorValue ou paleta); usada no card de preview com fundo pastel.
  final Color iconColor;
  /// Se não vazio, ao clicar "Acessar" abre tela com grid destes itens; cada um tem seu "Acessar" → url.
  final List<_SubLink>? subLinks;
  final bool isFavorite;

  const _LinkUtil({
    required this.title,
    required this.description,
    required this.url,
    required this.icon,
    required this.iconColor,
    this.subLinks,
    this.isFavorite = false,
  });

  bool get hasSubLinks => subLinks != null && subLinks!.isNotEmpty;

  static List<_LinkUtil> get lista => [
    _LinkUtil(title: 'CTB', description: 'Consulte o Código de Trânsito Brasileiro.', url: 'https://www.gov.br/infraestrutura/pt-br/assuntos/transito/conteudo-ctb/codigo-de-transito-brasileiro', icon: Icons.description_rounded, iconColor: AppColors.primary),
    _LinkUtil(title: 'Gov.br', description: 'Acesso aos serviços e informações do governo federal.', url: 'https://www.gov.br', icon: Icons.public_rounded, iconColor: AppColors.primary),
    _LinkUtil(title: 'Denatran', description: 'Departamento Nacional de Trânsito.', url: 'https://www.gov.br/infraestrutura/pt-br/assuntos/transito', icon: Icons.directions_car_rounded, iconColor: AppColors.primary),
    _LinkUtil(title: 'Débitos por estado', description: 'Consulte débitos de veículos por estado.', url: 'https://www.gov.br/infraestrutura/pt-br/assuntos/transito/conteudo-deten/divida-veicular', icon: Icons.search_rounded, iconColor: AppColors.primary, subLinks: _estadosBrasil),
    _LinkUtil(title: 'Normas e leis', description: 'Acesso a legislação e normas federais.', url: 'https://www.planalto.gov.br/ccivil_03/leis/l_9503.htm', icon: Icons.gavel_rounded, iconColor: AppColors.primary),
    _LinkUtil(title: 'Calculadoras úteis', description: 'Ferramentas práticas para cálculos do dia a dia.', url: 'https://www.gov.br', icon: Icons.calculate_rounded, iconColor: AppColors.primary),
  ];

  /// Estados do Brasil em ordem alfabética com URLs oficiais DETRAN/SEFAZ para consulta de débitos veiculares e IPVA.
  static const List<_SubLink> _estadosBrasil = [
    _SubLink(title: 'Acre', url: 'https://www.ac.getran.com.br/site/apps/veiculo/consulta/filtro-consulta-veiculo.jsp'),
    _SubLink(title: 'Alagoas', url: 'https://ipvaonline.sefaz.al.gov.br/'),
    _SubLink(title: 'Amapá', url: 'https://www.detran.ap.gov.br/detranap/'),
    _SubLink(title: 'Amazonas', url: 'https://digital.detran.am.gov.br/'),
    _SubLink(title: 'Bahia', url: 'https://www.detran.ba.gov.br/'),
    _SubLink(title: 'Ceará', url: 'https://ipva.sefaz.ce.gov.br/'),
    _SubLink(title: 'Distrito Federal', url: 'https://www.detran.df.gov.br/'),
    _SubLink(title: 'Espírito Santo', url: 'https://detran.es.gov.br/'),
    _SubLink(title: 'Goiás', url: 'https://sistemas.sefaz.go.gov.br/snc/publico/ipva/form'),
    _SubLink(title: 'Maranhão', url: 'https://www.detran.ma.gov.br/'),
    _SubLink(title: 'Mato Grosso', url: 'https://www.detran.mt.gov.br/'),
    _SubLink(title: 'Mato Grosso do Sul', url: 'https://servicos.efazenda.ms.gov.br/ipvapublico/Home/Index'),
    _SubLink(title: 'Minas Gerais', url: 'https://detran.mg.gov.br/veiculos/situacao-do-veiculo/consultar-situacao-do-veiculo'),
    _SubLink(title: 'Pará', url: 'https://www.detran.pa.gov.br/'),
    _SubLink(title: 'Paraíba', url: 'https://detran.pb.gov.br/veiculos/emissao-ipva'),
    _SubLink(title: 'Paraná', url: 'https://www.extratodebito.detran.pr.gov.br/detranextratos/geraExtrato.do'),
    _SubLink(title: 'Pernambuco', url: 'https://www.detran.pe.gov.br/'),
    _SubLink(title: 'Piauí', url: 'https://site.detran.pi.gov.br/taxas/debitos.php'),
    _SubLink(title: 'Rio de Janeiro', url: 'https://www.detran.rj.gov.br/'),
    _SubLink(title: 'Rio Grande do Norte', url: 'https://www.detran.rn.gov.br/'),
    _SubLink(title: 'Rio Grande do Sul', url: 'https://www.sefaz.rs.gov.br/apps/ipva/principal/tabs/consulta'),
    _SubLink(title: 'Rondônia', url: 'https://www.detran.ro.gov.br/'),
    _SubLink(title: 'Roraima', url: 'https://www.rr.getran.com.br/site/apps/veiculo/filtroplacarenavam-consultaveiculo.jsp'),
    _SubLink(title: 'Santa Catarina', url: 'https://servicos.detran.sc.gov.br/veiculos'),
    _SubLink(title: 'São Paulo', url: 'https://operacoes.sp.gov.br/DetranWeb/'),
    _SubLink(title: 'Sergipe', url: 'https://www.detran.se.gov.br/'),
    _SubLink(title: 'Tocantins', url: 'https://www.detran.to.gov.br/'),
  ];
}

/// Card na lista de links: barra azul + ícone colorido (mesma linguagem da lista de fornecedor / Yahweh).
class _LinkUtilCard extends StatelessWidget {
  final _LinkUtil link;

  const _LinkUtilCard({required this.link});

  @override
  Widget build(BuildContext context) {
    final icon = link.icon;
    final color = link.iconColor;

    Future<void> onOpen() async {
      if (link.hasSubLinks) {
        if (!context.mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _SubLinksScreen(
              title: link.title,
              gridTitle: link.title == 'Débitos por estado' ? 'ESTADOS DO BRASIL' : link.title,
              items: link.subLinks!,
            ),
          ),
        );
      } else {
        try {
          await openUrlPreferChrome(link.url);
        } catch (e) {
          debugPrint('Erro ao abrir link: $e');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Não foi possível abrir o link. Verifique se a URL é válida.'),
                backgroundColor: AppColors.error,
              ),
            );
          }
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppColors.deepBlueDark.withValues(alpha: 0.10),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Material(
            color: Colors.white,
            child: InkWell(
              onTap: () => onOpen(),
              splashColor: AppColors.primary.withValues(alpha: 0.08),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 5, color: AppColors.primary),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 14, 10, 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: color.withValues(alpha: 0.22)),
                              ),
                              child: Icon(icon, color: color, size: 26),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    link.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      color: AppColors.textPrimary,
                                      height: 1.2,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    link.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: GeminiTheme.textMuted,
                                      fontSize: 13,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (link.isFavorite)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Icon(Icons.star_rounded, size: 20, color: AppColors.amber),
                                  ),
                                Icon(
                                  Icons.open_in_new_rounded,
                                  size: 20,
                                  color: AppColors.primary.withValues(alpha: 0.88),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tela com grid de sub-itens (ex.: Estados do Brasil); cada item tem botão "→ Acessar".
class _SubLinksScreen extends StatelessWidget {
  final String title;
  final String gridTitle;
  final List<_SubLink> items;

  const _SubLinksScreen({
    required this.title,
    required this.gridTitle,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    const padding = 20.0;
    const spacing = 16.0;
    const crossAxisCount = 2;
    final cardWidth = (screenWidth - padding * 2 - spacing) / crossAxisCount;
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: GeminiTheme.background,
        appBar: AppBar(
          leadingWidth: 80,
          leading: _buildVoltarButtonAnotacoes(context),
          title: Text(title),
        ),
        body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(padding, 8, padding, padding + 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                gridTitle,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: GeminiTheme.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: items.map((item) => SizedBox(
                  width: cardWidth,
                  child: _SubLinkCard(item: item),
                )).toList(),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _SubLinkCard extends StatelessWidget {
  final _SubLink item;

  const _SubLinkCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      shadowColor: Colors.black12,
      borderRadius: BorderRadius.circular(GeminiTheme.cardRadius),
      color: GeminiTheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: GeminiTheme.textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  try {
                    await openUrlPreferChrome(item.url);
                  } catch (e) {
                    debugPrint('Erro ao abrir link: $e');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Não foi possível abrir o link. Verifique se a URL é válida.'),
                          backgroundColor: AppColors.error,
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('Acessar'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GeminiTheme.buttonRadius)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteFormSheet extends StatefulWidget {
  final String uid;
  final NoteEntry? existing;
  final TextEditingController titleCtrl;
  final TextEditingController itemsCtrl;

  const _NoteFormSheet({
    required this.uid,
    required this.existing,
    required this.titleCtrl,
    required this.itemsCtrl,
  });

  @override
  State<_NoteFormSheet> createState() => _NoteFormSheetState();
}

class _NoteFormSheetState extends State<_NoteFormSheet> {
  late DateTime _date;
  late int _colorIndex;

  @override
  void initState() {
    super.initState();
    _date = widget.existing?.date ?? DateTime.now();
    _colorIndex = widget.existing?.colorIndex ?? 0;
  }

  Future<void> _save() async {
    final title = widget.titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o título.')),
      );
      return;
    }
    final items = widget.itemsCtrl.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final note = NoteEntry(
      id: widget.existing?.id ?? '',
      title: title,
      date: _date,
      colorIndex: _colorIndex,
      items: items,
      isPinned: widget.existing?.isPinned ?? false,
      createdAt: widget.existing?.createdAt,
      updatedAt: widget.existing?.updatedAt,
    );
    final isEdit = widget.existing != null;
    if (isEdit) {
      await NotesService().update(widget.uid, note);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Anotação atualizada.')));
      }
    } else {
      await NotesService().add(widget.uid, note);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Anotação criada.')));
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: GeminiTheme.surface,
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          tooltip: 'Fechar',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.maybePop(context),
          style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
        title: Text(
          isEdit ? 'Editar anotação' : 'Nova anotação',
          style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 14, 24, 24 + safeBottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              const SizedBox(height: 4),
              FastTextField(
                controller: widget.titleCtrl,
                decoration: InputDecoration(
                  labelText: 'Título',
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(GeminiTheme.inputRadius), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Data'),
                subtitle: Text(DateFormat('dd/MM/yyyy').format(_date)),
                trailing: const Icon(Icons.calendar_today_rounded),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null && mounted) setState(() => _date = picked);
                },
              ),
              const SizedBox(height: 12),
              const Text('Cor da categoria', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                children: List.generate(4, (i) {
                  final selected = _colorIndex == i;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _colorIndex = i),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _noteCategoryColors[i],
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? Colors.white : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _noteCategoryColors[i].withValues(alpha: 0.5),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),
              FastTextField(
                controller: widget.itemsCtrl,
                decoration: InputDecoration(
                  labelText: 'Itens (um por linha)',
                  hintText: 'Item 1\nItem 2\nItem 3',
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(GeminiTheme.inputRadius), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GeminiTheme.buttonRadius)),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(GeminiTheme.buttonRadius),
                        gradient: const LinearGradient(
                          colors: [AppColors.deepBlueDark, AppColors.primary, AppColors.accent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.deepBlueDark.withValues(alpha: 0.28),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _save,
                          borderRadius: BorderRadius.circular(GeminiTheme.buttonRadius),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: Text(
                                isEdit ? 'Salvar' : 'Adicionar',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ),
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
}

class _NoteCard extends StatelessWidget {
  final NoteEntry note;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onPin;
  /// Contexto do alvo para [Share.share] (popover iPad / Android estável).
  final void Function(BuildContext anchorContext)? onShare;
  final VoidCallback? onCopy;
  final bool canEdit;

  const _NoteCard({
    super.key,
    required this.note,
    required this.onEdit,
    required this.onDelete,
    this.onPin,
    this.onShare,
    this.onCopy,
    required this.canEdit,
  });

  @override
  Widget build(BuildContext context) {
    final accentBlue = AppColors.primary;
    final radius = BorderRadius.circular(18);
    final rawTitle = note.title.trim().isEmpty ? 'Sem título' : note.title.trim();
    final titleText = rawTitle.replaceAll(RegExp(r'[\r\n\u200B]+'), ' ').trim();

    final d = note.date;
    final dateStr = DateFormat('dd/MM/yyyy').format(d);
    final hasTime = d.hour != 0 || d.minute != 0;
    final timePart = hasTime ? ' às ${DateFormat('HH:mm').format(d)}' : '';
    final n = note.items.length;
    final itemsPart = n > 0 ? ' • $n ${n == 1 ? 'item' : 'itens'}' : '';
    final metaLine = '$dateStr$timePart$itemsPart';

    String? preview;
    if (note.items.isNotEmpty) {
      final first = note.items.first.trim();
      if (first.isNotEmpty) {
        preview = first.length > 80 ? '${first.substring(0, 80)}…' : first;
      }
    }

    final hasExtra = onPin != null || onCopy != null || onShare != null;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: AppColors.deepBlueDark.withValues(alpha: 0.10),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 6, color: accentBlue),
                Expanded(
                  child: Material(
                    color: Colors.white,
                    child: InkWell(
                      onTap: canEdit ? onEdit : null,
                      splashColor: accentBlue.withValues(alpha: 0.08),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (note.isPinned) ...[
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2, right: 6),
                                    child: Icon(Icons.push_pin_rounded, size: 18, color: accentBlue),
                                  ),
                                ],
                                Expanded(
                                  child: Text(
                                    titleText,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      height: 1.25,
                                      color: Color(0xFF0F172A),
                                    ),
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              metaLine,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.3,
                                color: AppColors.textMuted,
                              ),
                            ),
                            if (preview != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                preview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  color: const Color(0xFF0F172A).withValues(alpha: 0.72),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (canEdit)
                  Padding(
                    padding: const EdgeInsets.only(right: 4, top: 2, bottom: 2),
                    child: SizedBox(
                      width: hasExtra ? 96 : 48,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (hasExtra)
                                PopupMenuButton<String>(
                                  padding: EdgeInsets.zero,
                                  tooltip: 'Mais opções',
                                  icon: Icon(Icons.more_vert_rounded, size: 22, color: AppColors.textSecondary),
                                  onSelected: (v) {
                                    if (v == 'pin') onPin?.call();
                                    if (v == 'copy') onCopy?.call();
                                    if (v == 'share') onShare?.call(context);
                                  },
                                  itemBuilder: (_) => [
                                    if (onPin != null)
                                      PopupMenuItem(
                                        value: 'pin',
                                        child: Text(note.isPinned ? 'Desfixar' : 'Fixar no topo'),
                                      ),
                                    if (onCopy != null) const PopupMenuItem(value: 'copy', child: Text('Copiar texto')),
                                    if (onShare != null) const PopupMenuItem(value: 'share', child: Text('Compartilhar')),
                                  ],
                                ),
                              IconButton(
                                onPressed: onEdit,
                                tooltip: 'Editar',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                                icon: Icon(Icons.edit_rounded, color: _yahwehEditGreen, size: 24),
                              ),
                            ],
                          ),
                          IconButton(
                            onPressed: onDelete,
                            tooltip: 'Excluir',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                            icon: Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 24),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
