import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/scale_entry.dart';
import '../models/user_profile.dart';
import '../screens/compromisso_form_page.dart';
import '../theme/app_colors.dart';
import '../utils/scale_entry_sei_ocorrencia.dart';
import '../widgets/lancamento_expresso_plantao_sheet.dart';
import 'agenda_reminder_edit_service.dart';
import 'express_compromisso_agenda_sync.dart';

/// Abre [CompromissoFormPage] / compromisso expresso em tela cheia.
class ScaleEntryAgendaEdit {
  ScaleEntryAgendaEdit._();

  static Future<String?> resolveAgendaReminderId({
    required String userDocId,
    required ScaleEntry entry,
  }) async {
    final fromDocId =
        ExpressCompromissoAgendaSync.reminderIdFromScaleDocId(entry.id);
    if (fromDocId != null) return fromDocId;

    final id = entry.id?.trim() ?? '';
    if (id.startsWith('agenda_')) {
      final aid = id.substring('agenda_'.length).trim();
      if (aid.isNotEmpty) return aid;
    }
    if (id.isEmpty) return null;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(userDocId)
          .collection('scales')
          .doc(id)
          .get();
      final aid = (snap.data()?['agendaId'] ?? '').toString().trim();
      if (aid.isNotEmpty) return aid;
    } catch (_) {}
    return null;
  }

  /// Retorna mensagem de sucesso ou `null` se cancelou / falhou silenciosamente.
  static Future<String?> openFullEditor({
    required BuildContext context,
    required ScaleEntry entry,
    required String userDocId,
    required UserProfile profile,
  }) async {
    final agendaId = await resolveAgendaReminderId(
      userDocId: userDocId,
      entry: entry,
    );
    if (!context.mounted) return null;
    if (agendaId == null || agendaId.isEmpty) {
      return null;
    }

    try {
      final q = await FirebaseFirestore.instance
          .collection('users')
          .doc(userDocId)
          .collection('reminders')
          .where(FieldPath.documentId, isEqualTo: agendaId)
          .limit(1)
          .get();
      if (!context.mounted) return null;
      if (q.docs.isEmpty) {
        return null;
      }
      final reminderDoc = q.docs.first;

      final nav = Navigator.of(context, rootNavigator: true);

      final result = await nav.push<CompromissoFormResult?>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => CompromissoFormPage(
            profile: profile,
            hasActiveLicense: profile.hasActiveLicense,
            existingDoc: reminderDoc,
          ),
        ),
      );
      if (result == null || !context.mounted) return null;
      return AgendaReminderEditService.persistCompromissoEdit(
        doc: reminderDoc,
        result: result,
        userDocId: userDocId,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao carregar Agenda: ${e.toString().split('\n').first}',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return null;
    }
  }

  /// Compromisso particular sem vínculo Agenda — mesma tela do painel (expresso).
  static Future<void> openCompromissoParticularExpress({
    required BuildContext context,
    required ScaleEntry entry,
    required String userDocId,
    VoidCallback? onSaved,
  }) async {
    await showLancamentoExpressoPlantaoSheet(
      context: context,
      uid: userDocId,
      day: entry.date,
      lockDate: true,
      initialFinanceiro: false,
      editingEntry: entry,
      onSalvar: () => onSaved?.call(),
    );
  }

  /// Roteia edição: tela cheia (Agenda / expresso) ou dialog rápido de nº escala (plantão).
  static Future<void> editScaleEntry({
    required BuildContext context,
    required ScaleEntry entry,
    required String userDocId,
    required UserProfile profile,
    required Future<void> Function() onPlantaoQuickEdit,
    VoidCallback? onSaved,
  }) async {
    if (!scaleEntryRequiresFullEditor(entry)) {
      await onPlantaoQuickEdit();
      return;
    }

    final msg = await openFullEditor(
      context: context,
      entry: entry,
      userDocId: userDocId,
      profile: profile,
    );
    if (msg != null) {
      onSaved?.call();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
      return;
    }

    if (entry.isCompromisso &&
        !scaleEntryIsPlantaoParaEdicaoRapida(entry) &&
        context.mounted) {
      await openCompromissoParticularExpress(
        context: context,
        entry: entry,
        userDocId: userDocId,
        onSaved: onSaved,
      );
      return;
    }

    if (scaleEntryUsesAgendaFullEditor(entry) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível abrir a edição. Abra o módulo Agenda.',
          ),
        ),
      );
      return;
    }

    await onPlantaoQuickEdit();
  }
}
