import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import 'agenda_notification_reschedule_helper.dart';
import 'agenda_notifications_refresher.dart';
import 'agenda_scale_mirror_service.dart';
import 'yearly_commitment_repeat_service.dart';

/// Escopo da exclusão de compromisso com repetição anual.
enum AgendaYearlyDeleteScope {
  cancel,
  thisYearOnly,
  allYears,
}

/// Apaga anexos de audiência no Storage (ofício, etc.).
Future<void> deleteAudienciaStorageForReminder({
  required String userDocId,
  required String reminderDocId,
}) async {
  if (userDocId.isEmpty || reminderDocId.isEmpty) return;
  try {
    final pref = FirebaseStorage.instance
        .ref('users/$userDocId/audiencias/$reminderDocId');
    final list = await pref.listAll();
    for (final it in list.items) {
      await it.delete();
    }
    for (final p in list.prefixes) {
      final sub = await p.listAll();
      for (final it in sub.items) {
        await it.delete();
      }
    }
  } catch (_) {}
}

/// Pergunta: remover só este ano ou toda a série anual.
Future<AgendaYearlyDeleteScope> askYearlyDeleteScope(
  BuildContext context, {
  required int? instanceYear,
  required String title,
}) async {
  final yearLabel = instanceYear != null ? ' de $instanceYear' : '';
  final choice = await showDialog<AgendaYearlyDeleteScope>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Excluir compromisso anual?'),
      content: Text(
        '«$title»$yearLabel faz parte de uma série que repete todo ano.\n\n'
        'Deseja remover apenas esta ocorrência ou cancelar a repetição em todos os anos?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, AgendaYearlyDeleteScope.cancel),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(ctx, AgendaYearlyDeleteScope.thisYearOnly),
          child: Text('Só este ano${instanceYear != null ? ' ($instanceYear)' : ''}'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, AgendaYearlyDeleteScope.allYears),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFB91C1C),
          ),
          child: const Text('Todos os anos'),
        ),
      ],
    ),
  );
  return choice ?? AgendaYearlyDeleteScope.cancel;
}

/// Remove lembrete na Agenda + espelho em Escalas (sem diálogo).
Future<bool> deleteAgendaReminderCore({
  required String userDocId,
  required String reminderDocId,
  required bool isAudiencia,
}) async {
  if (userDocId.isEmpty || reminderDocId.isEmpty) return false;
  try {
    if (isAudiencia) {
      await deleteAudienciaStorageForReminder(
        userDocId: userDocId,
        reminderDocId: reminderDocId,
      );
    }
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userDocId)
        .collection('reminders')
        .doc(reminderDocId)
        .delete();
    await AgendaScaleMirrorService.delete(
      userDocId: userDocId,
      agendaId: reminderDocId,
    );
    unawaited(AgendaNotificationsRefresher.refresh(uid: userDocId));
    return true;
  } catch (_) {
    return false;
  }
}

/// Exclusão em lote (Agenda → calendário Escalas via espelho).
Future<int> deleteAgendaRemindersBatch({
  required BuildContext context,
  required String userDocId,
  required List<({String id, bool isAudiencia, Map<String, dynamic>? data})>
      items,
  required String confirmTitle,
  required String confirmMessage,
}) async {
  if (items.isEmpty || userDocId.isEmpty) return 0;
  final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(confirmTitle),
          content: Text(confirmMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB91C1C),
              ),
              child: const Text('Excluir'),
            ),
          ],
        ),
      ) ??
      false;
  if (!ok || !context.mounted) return 0;

  var n = 0;
  for (final it in items) {
    final okOne = await _deleteOneInBatch(
      context: context,
      userDocId: userDocId,
      reminderDocId: it.id,
      isAudiencia: it.isAudiencia,
      data: it.data,
    );
    if (okOne) n++;
  }
  if (context.mounted && n > 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          n == 1 ? '1 item excluído.' : '$n itens excluídos.',
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
  return n;
}

Future<bool> _deleteOneInBatch({
  required BuildContext context,
  required String userDocId,
  required String reminderDocId,
  required bool isAudiencia,
  Map<String, dynamic>? data,
}) async {
  if (!isAudiencia &&
      data != null &&
      YearlyCommitmentRepeatService.isYearlyRepeatEntry(data)) {
    final scope = await askYearlyDeleteScope(
      context,
      instanceYear: YearlyCommitmentRepeatService.instanceYearFromData(
        data,
        docId: reminderDocId,
      ),
      title: (data['title'] ?? 'Compromisso').toString(),
    );
    if (!context.mounted || scope == AgendaYearlyDeleteScope.cancel) {
      return false;
    }
    if (scope == AgendaYearlyDeleteScope.allYears) {
      final tid = YearlyCommitmentRepeatService.templateIdFromReminderData(
        data,
        reminderDocId,
      );
      if (tid != null) {
        await YearlyCommitmentRepeatService.deleteYearlySeries(
          userDocId: userDocId,
          templateId: tid,
        );
        return true;
      }
    }
    await YearlyCommitmentRepeatService.deleteYearlyInstanceOnly(
      userDocId: userDocId,
      instanceReminderDocId: reminderDocId,
      instanceData: data,
    );
    return true;
  }
  return deleteAgendaReminderCore(
    userDocId: userDocId,
    reminderDocId: reminderDocId,
    isAudiencia: isAudiencia,
  );
}

/// Remove lembrete na Agenda e o espelho em Escalas; tenta apagar anexos no Storage (audiência).
Future<bool> deleteAgendaReminder({
  required BuildContext context,
  required String userDocId,
  required String reminderDocId,
  required bool isAudiencia,
  Map<String, dynamic>? reminderData,
}) async {
  Map<String, dynamic>? data = reminderData;
  if (data == null && userDocId.isNotEmpty) {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(userDocId)
          .collection('reminders')
          .doc(reminderDocId)
          .get();
      data = snap.data();
    } catch (_) {}
  }

  if (!isAudiencia &&
      data != null &&
      YearlyCommitmentRepeatService.isYearlyRepeatEntry(data)) {
    final scope = await askYearlyDeleteScope(
      context,
      instanceYear: YearlyCommitmentRepeatService.instanceYearFromData(
        data,
        docId: reminderDocId,
      ),
      title: (data['title'] ?? 'Compromisso').toString().trim().isEmpty
          ? 'Compromisso'
          : (data['title'] ?? 'Compromisso').toString(),
    );
    if (!context.mounted || scope == AgendaYearlyDeleteScope.cancel) {
      return false;
    }
    try {
      if (scope == AgendaYearlyDeleteScope.allYears) {
        final tid = YearlyCommitmentRepeatService.templateIdFromReminderData(
          data,
          reminderDocId,
        );
        if (tid == null) return false;
        await YearlyCommitmentRepeatService.deleteYearlySeries(
          userDocId: userDocId,
          templateId: tid,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Série anual removida (todos os anos, Agenda e Escalas).',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return true;
      }
      await YearlyCommitmentRepeatService.deleteYearlyInstanceOnly(
        userDocId: userDocId,
        instanceReminderDocId: reminderDocId,
        instanceData: data,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ocorrência deste ano removida (Agenda e calendário de Escalas).',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao excluir: ${e.toString().split('\n').first}'),
            backgroundColor: const Color(0xFFB91C1C),
          ),
        );
      }
      return false;
    }
  }

  final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Excluir da Agenda?'),
          content: Text(
            isAudiencia
                ? 'A audiência e o espelho no calendário de Escalas serão removidos.'
                : 'O compromisso e o espelho no calendário de Escalas serão removidos.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB91C1C),
              ),
              child: const Text('Excluir'),
            ),
          ],
        ),
      ) ??
      false;
  if (!ok || !context.mounted) return false;

  try {
    final okCore = await deleteAgendaReminderCore(
      userDocId: userDocId,
      reminderDocId: reminderDocId,
      isAudiencia: isAudiencia,
    );
    if (!okCore) throw Exception('Falha ao excluir');

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isAudiencia ? 'Audiência excluída.' : 'Compromisso excluído.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao excluir: ${e.toString().split('\n').first}'),
          backgroundColor: const Color(0xFFB91C1C),
        ),
      );
    }
    return false;
  }
}
