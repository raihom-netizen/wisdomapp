import 'package:cloud_firestore/cloud_firestore.dart';

/// «⏰ Despertar no horário» — modo POR ITEM de compromisso particular.
///
/// Com o interruptor ligado o servidor (`functions/agenda_despertador.js`)
/// cria o aviso NO horário (lead 0) e ele chega como despertador: toque longo,
/// botões Adiar/Encerrar e repetições (3× a cada 3 min, ou as do despertador
/// do módulo Compromissos) — mesmo com o despertador geral desligado. Passou
/// o horário e as repetições, nada mais toca; «Encerrar» conclui o item.
///
/// Os campos vão no reminder E no espelho `scales/agenda_{id}` (o espelho só
/// usa para mostrar o ⏰ no calendário). O bot do Telegram grava os mesmos.
const String kDespertadorField = 'despertador';

/// Cria o aviso de lead 0 (no horário exato).
const String kAvisarNoHorarioField = 'avisarNoHorario';

/// Só no horário (sem os avisos antecipados de «Quando avisar») — gravado
/// pelo lembrete rápido do bot; o app preserva o valor que já estiver lá.
const String kApenasNoHorarioField = 'apenasNoHorario';

/// O compromisso tem o despertador no horário ligado?
bool compromissoTemDespertador(Map<String, dynamic>? data) =>
    data != null && data[kDespertadorField] == true;

/// Campos para um documento NOVO (create): só entram quando ligado.
Map<String, dynamic> camposDespertadorNovo(bool ligado) => ligado
    ? const {kDespertadorField: true, kAvisarNoHorarioField: true}
    : const <String, dynamic>{};

/// Campos para EDIÇÃO (update/merge): ligado grava; desligado apaga.
Map<String, dynamic> camposDespertadorEdicao(bool ligado) => ligado
    ? {kDespertadorField: true, kAvisarNoHorarioField: true}
    : {
        kDespertadorField: FieldValue.delete(),
        kAvisarNoHorarioField: FieldValue.delete(),
        kApenasNoHorarioField: FieldValue.delete(),
      };
