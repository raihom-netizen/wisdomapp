import 'package:firebase_auth/firebase_auth.dart';

import 'package:intl/intl.dart';

import 'notification_module_theme.dart';



/// Textos premium unificados — iOS, Android e Web/PWA (local + plano de agenda).

/// Push com app fechado: `functions/agenda_message_templates.js` (mesma regra).

///

/// Marca exibida em e-mails e fallbacks de push: [kNotificationBrandApp].

const String kNotificationBrandApp = 'WISDOMAPP';



/// Contexto para textos premium — Controle Total App.

class NotificationMessageContext {

  const NotificationMessageContext({

    this.userName,

    this.eventTitle = '',

    this.eventAt,

    this.timeStr = '',

    this.endStr = '',

    this.local = '',

    this.sala = '',

    this.processo = '',

    this.numeroOcorrencia = '',

    this.cliente = '',

    this.leadMin,

    this.isConfirmed = false,

    this.channelKind = 'compromisso',

    this.modalityLabel = '',

  });



  final String? userName;

  final String eventTitle;

  final DateTime? eventAt;

  final String timeStr;

  final String endStr;

  final String local;

  final String sala;

  final String processo;

  final String numeroOcorrencia;

  final String cliente;

  final int? leadMin;

  final bool isConfirmed;

  final String channelKind;

  /// Audiência: «ON LINE» ou «PRESENCIAL» (push não leva link/endereço completo).

  final String modalityLabel;

}



/// Online vs presencial — alinhado a [agenda_message_templates.js].

({bool isOnline, String modalityLabel, String link, String address})

    _resolveAudienciaModality(Map<String, dynamic> d) {

  final local = (d['localAudiencia'] ?? '').toString().trim();

  final link = (d['linkSalaAudiencia'] ?? '').toString().trim();

  final ll = local.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  final isOnline = link.isNotEmpty ||

      ll == 'on line' ||

      ll == 'online' ||

      ll.contains('on line');

  if (isOnline) {

    return (

      isOnline: true,

      modalityLabel: 'ON LINE',

      link: link,

      address: '',

    );

  }

  var address = local;

  if (ll == 'presencial') address = '';

  if (address.isEmpty) address = 'Endereço não informado';

  return (

    isOnline: false,

    modalityLabel: 'PRESENCIAL',

    link: '',

    address: address,

  );

}



/// Textos premium unificados — **iOS, Android e Web/PWA** (local + plano de agenda).

/// Push com app fechado usa a mesma biblioteca no servidor (`agenda_message_templates.js`).

class NotificationMessageBuilder {

  NotificationMessageBuilder._();



  static String? get _defaultUserName {

    final u = FirebaseAuth.instance.currentUser;

    final n = (u?.displayName ?? '').trim();

    return n.isEmpty ? null : n;

  }



  static int _normalizeLeadMinutes(int? leadMin) {

    if (leadMin == null || leadMin <= 0) return 0;

    for (final bucket in [1440, 60, 30, 15]) {

      if ((leadMin - bucket).abs() <= 5) return bucket;

    }

    return leadMin;

  }



  static String leadTitlePrefix(int? leadMin) {

    final m = _normalizeLeadMinutes(leadMin);

    if (m <= 0) return 'Lembrete';

    if (m >= 1440) {

      final d = (m / 1440).round();

      return d == 1 ? '1 dia antes' : '$d dias antes';

    }

    if (m == 60) return '1 hora antes';

    if (m == 30) return '30 minutos antes';

    if (m == 15) return '15 minutos antes';

    if (m > 60) {

      final h = (m / 60).round();

      return h == 1 ? '1 hora antes' : '$h horas antes';

    }

    return m == 1 ? '1 minuto antes' : '$m minutos antes';

  }



  static String _channelKindLabel(String channelKind) {

    switch (channelKind) {

      case 'escala':

        return 'Escala';

      case 'audiencia':

        return 'Audiência';

      case 'compromisso':

        return 'Compromisso';

      default:

        return 'Agenda';

    }

  }



  static String _formatTimeHm(String str) {

    final parts = str.split(':');

    final h = (int.tryParse(parts.first) ?? 0).toString().padLeft(2, '0');

    final m = parts.length > 1

        ? (int.tryParse(parts[1]) ?? 0).toString().padLeft(2, '0')

        : '00';

    return '${h}h$m';

  }



  static ({String headline, String whenWord, String dateStr}) _eventDayContext(

    DateTime? eventAt,

  ) {

    if (eventAt == null) {

      return (headline: '', whenWord: '', dateStr: '');

    }

    final now = DateTime.now();

    final sameDay = eventAt.year == now.year &&

        eventAt.month == now.month &&

        eventAt.day == now.day;

    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    final isTomorrow = eventAt.year == tomorrow.year &&

        eventAt.month == tomorrow.month &&

        eventAt.day == tomorrow.day;

    final dateStr = DateFormat('dd/MM/yyyy').format(eventAt);

    if (isTomorrow) {

      return (headline: 'Amanhã', whenWord: 'amanhã', dateStr: dateStr);

    }

    if (sameDay) {

      return (headline: 'Hoje', whenWord: 'hoje', dateStr: dateStr);

    }

    return (headline: '', whenWord: '', dateStr: dateStr);

  }



  static String? _leadTimingPhrase(int lead) {

    if (lead >= 1440) return null;

    if (lead == 60) return 'em 1 hora';

    if (lead == 30) return 'em 30 minutos';

    if (lead == 15) return 'em 15 minutos';

    if (lead > 60) {

      final h = (lead / 60).round();

      return h == 1 ? 'em 1 hora' : 'em $h horas';

    }

    return lead == 1 ? 'em 1 minuto' : 'em $lead minutos';

  }



  static String _pushTitle(int? leadMin, String channelKind) {

    return '${leadTitlePrefix(leadMin)} — ${_channelKindLabel(channelKind)}';

  }

  static String _compactTitleDetail(String value, {int max = 42}) {
    final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) return '';
    if (clean.length <= max) return clean;
    return '${clean.substring(0, max - 1).trimRight()}…';
  }



  /// Subtítulo iOS / agrupamento — paridade com `pushSubtitle` no servidor.

  static String pushSubtitle(int? leadMin, String channelKind) {

    return '${_channelKindLabel(channelKind)} · ${leadTitlePrefix(leadMin)}';

  }



  /// Cor do ícone no Android (ARGB).

  static int androidNotificationColor(String channelKind) {

    return NotificationModuleTheme.forKind(channelKind).colorArgb;

  }



  /// Escalas (plantão) ou compromisso em `scales`.

  static ({String title, String body}) buildScaleNotificationMessage(

    Map<String, dynamic> d, {

    String? userName,

    DateTime? eventAt,

    int? leadMin,

  }) {

    final isCompromisso = (d['isCompromisso'] ?? false) as bool;

    if (isCompromisso) {

      return buildCompromissoNotification(

        title: ((d['label'] ?? d['scaleLocationName']) ?? '').toString().trim(),

        hora: (d['start'] ?? '08:00').toString(),

        local: (d['notes'] ?? '').toString().trim(),

        cliente: '',

        userName: userName,

        eventAt: eventAt,

        leadMin: leadMin,

      );

    }

    final label = ((d['label'] ?? d['scaleLocationName']) ?? '').toString().trim();

    final abbreviation = (d['abbreviation'] ?? '').toString().trim();

    final startStr = (d['start'] ?? '08:00').toString();

    final endStr = (d['end'] ?? '18:00').toString();

    final local = abbreviation.isNotEmpty

        ? abbreviation

        : (label.isEmpty ? 'Plantão' : label);

    return buildEscalaNotification(

      local: local,

      hora: startStr,

      endStr: endStr,

      userName: userName,

      eventAt: eventAt,

      leadMin: leadMin,

      titulo: label,

    );

  }



  /// Audiência — push/local premium.

  static ({String title, String body}) buildAudienciaNotification({

    required String proc,

    required String hora,

    required String local,

    String? sala,

    String? userName,

    DateTime? eventAt,

    int? leadMin,

    bool confirmed = false,

  }) {

    final mod = _resolveAudienciaModality({

      'type': 'audiencia',

      'localAudiencia': local,

      'linkSalaAudiencia': sala ?? '',

    });

    final ctx = NotificationMessageContext(

      userName: userName,

      eventTitle: 'Audiência',

      eventAt: eventAt,

      timeStr: hora,

      local: mod.isOnline ? '' : mod.address,

      sala: mod.isOnline ? mod.link : '',

      processo: proc,

      leadMin: leadMin,

      isConfirmed: confirmed,

      channelKind: 'audiencia',

      modalityLabel: mod.modalityLabel,

    );

    return _buildAudiencia(ctx);

  }



  /// Compromisso — agenda/reminders.

  static ({String title, String body}) buildCompromissoNotification({

    required String title,

    required String hora,

    required String local,

    String cliente = '',

    String? userName,

    DateTime? eventAt,

    int? leadMin,

    bool confirmed = false,

  }) {

    final ctx = NotificationMessageContext(

      userName: userName,

      eventTitle: title.isEmpty ? 'Compromisso' : title,

      eventAt: eventAt,

      timeStr: hora,

      local: local,

      cliente: cliente,

      leadMin: leadMin,

      isConfirmed: confirmed,

      channelKind: 'compromisso',

    );

    return _buildCompromisso(ctx);

  }



  /// Plantão / escala.

  static ({String title, String body}) buildEscalaNotification({

    required String local,

    required String hora,

    String endStr = '18:00',

    String titulo = '',

    String? userName,

    DateTime? eventAt,

    int? leadMin,

  }) {

    final ctx = NotificationMessageContext(

      userName: userName,

      eventTitle: titulo.isEmpty ? 'Plantão' : titulo,

      eventAt: eventAt,

      timeStr: hora,

      endStr: endStr,

      local: local,

      leadMin: leadMin,

      channelKind: 'escala',

    );

    return _buildEscala(ctx);

  }



  static ({String title, String body}) buildContaPagarNotification({

    required String desc,

    required String valor,

    String? userName,

    DateTime? eventAt,

    int? leadMin,

  }) {

    final greet = _greet(userName);
    final dateStr =
        eventAt != null ? DateFormat('dd/MM/yyyy').format(eventAt) : '';
    final whenLine = dateStr.isEmpty
        ? 'Conta a pagar vence hoje:'
        : 'Conta a pagar vence em $dateStr:';
    final titleDetail = _compactTitleDetail(desc);

    return (

      title: titleDetail.isEmpty
          ? '${leadTitlePrefix(leadMin)} — Financeiro'
          : '${leadTitlePrefix(leadMin)} — Financeiro: $titleDetail',

      body: '$greet 👋\n\n'

          '$whenLine\n'

          '📌 $desc\n'

          '💵 Valor: R\$ $valor\n\n'

          '✅ Pague pelo app e mantenha seu histórico em dia.\n\n'

          'Toque para abrir o financeiro.',

    );

  }



  static ({String title, String body}) buildContaReceberNotification({

    required String desc,

    required String valor,

    String? userName,

    DateTime? eventAt,

    int? leadMin,

  }) {

    final greet = _greet(userName);
    final dateStr =
        eventAt != null ? DateFormat('dd/MM/yyyy').format(eventAt) : '';
    final whenLine = dateStr.isEmpty
        ? 'Conta a receber vence hoje:'
        : 'Conta a receber vence em $dateStr:';
    final titleDetail = _compactTitleDetail(desc);

    return (

      title: titleDetail.isEmpty
          ? '${leadTitlePrefix(leadMin)} — Financeiro'
          : '${leadTitlePrefix(leadMin)} — Financeiro: $titleDetail',

      body: '$greet 👋\n\n'

          '$whenLine\n'

          '📌 $desc\n'

          '💰 Valor: R\$ $valor\n\n'

          '✅ Registre o recebimento pelo app e mantenha seu histórico em dia.\n\n'

          'Toque para abrir o financeiro.',

    );

  }



  /// Monta contexto a partir de documento Firestore `reminders`.

  static NotificationMessageContext contextFromReminder(

    Map<String, dynamic> d, {

    String? userName,

    DateTime? eventAt,

    int? leadMin,

  }) {

    final type = (d['type'] ?? 'compromisso').toString();

    final isAud = type == 'audiencia';

    final title = (d['title'] ?? '').toString().trim();

    final timeStr = (d['time'] ?? '').toString();

    final localAud = (d['localAudiencia'] ?? '').toString().trim();

    final linkSala = (d['linkSalaAudiencia'] ?? '').toString().trim();

    final sei = (d['numeroSei'] ?? '').toString().trim();

    final oco = (d['numeroOcorrencia'] ?? '').toString().trim();

    final status = (d['status'] ?? 'EM_ABERTO').toString();

    final confirmed = status == 'REALIZADO' || (d['done'] == true);

    final mod = isAud ? _resolveAudienciaModality(d) : null;

    return NotificationMessageContext(

      userName: userName,

      eventTitle: title.isEmpty

          ? (isAud ? 'Audiência' : 'Compromisso')

          : title,

      eventAt: eventAt,

      timeStr: timeStr,

      local: mod != null && !mod.isOnline ? mod.address : localAud,

      sala: mod != null && mod.isOnline ? mod.link : '',

      processo: sei,

      numeroOcorrencia: oco,

      cliente: (d['cliente'] ?? d['notes'] ?? '').toString().trim(),

      leadMin: leadMin,

      isConfirmed: confirmed,

      channelKind: isAud ? 'audiencia' : 'compromisso',

      modalityLabel: mod?.modalityLabel ?? '',

    );

  }



  static ({String title, String body}) fromReminderDoc(

    Map<String, dynamic> d, {

    String? userName,

    DateTime? eventAt,

    int? leadMin,

  }) {

    final ctx = contextFromReminder(d, userName: userName, eventAt: eventAt, leadMin: leadMin);

    if (ctx.channelKind == 'audiencia') return _buildAudiencia(ctx);

    return _buildCompromisso(ctx);

  }



  static String _greet(String? userName) {

    final n = (userName ?? _defaultUserName ?? '').trim();

    if (n.isEmpty) return 'Olá';

    final parts = n.split(RegExp(r'\s+'));

    final first = parts.first;

    if (parts.length >= 2 && first.length <= 4) {

      return 'Olá, $first ${parts[1]}';

    }

    return 'Olá, $first';

  }



  static ({String title, String body}) _buildAudiencia(

    NotificationMessageContext ctx,

  ) {

    final day = _eventDayContext(ctx.eventAt);

    final startHm = _formatTimeHm(ctx.timeStr);

    final dateStr = day.dateStr.isNotEmpty

        ? day.dateStr

        : (ctx.eventAt != null

            ? DateFormat('dd/MM/yyyy').format(ctx.eventAt!)

            : '');

    final titleDetail = _compactTitleDetail(
      ctx.eventTitle.isNotEmpty && ctx.eventTitle != 'Audiência'
          ? ctx.eventTitle
          : (ctx.processo.isNotEmpty ? 'SEI ${ctx.processo}' : ''),
    );

    final title = titleDetail.isEmpty
        ? _pushTitle(ctx.leadMin, 'audiencia')
        : '${leadTitlePrefix(ctx.leadMin)} — Audiência: $titleDetail';

    final modLabel =

        ctx.modalityLabel.isNotEmpty ? ctx.modalityLabel : 'PRESENCIAL';

    final greet = _greet(ctx.userName);



    final lines = <String>['📅 $dateStr · 🕒 $startHm'];

    if (ctx.processo.isNotEmpty) {

      lines.add('📂 Nº SEI: ${ctx.processo}');

    }

    if (ctx.numeroOcorrencia.isNotEmpty) {

      lines.add('🏷️ Nº Ocorrência: ${ctx.numeroOcorrencia}');

    }

    lines.add('📍 $modLabel');

    if (ctx.eventTitle.isNotEmpty && ctx.eventTitle != 'Audiência') {

      lines.add('📝 ${ctx.eventTitle}');

    }

    lines.add('');

    lines.add('Toque para abrir os detalhes.');

    var body = lines.join('\n');

    if (greet != 'Olá') body = '$greet,\n\n$body';

    return (title: title, body: body);

  }



  static ({String title, String body}) _buildCompromisso(

    NotificationMessageContext ctx,

  ) {

    final day = _eventDayContext(ctx.eventAt);

    final startHm = _formatTimeHm(ctx.timeStr);

    final dateStr = day.dateStr.isNotEmpty

        ? day.dateStr

        : (ctx.eventAt != null

            ? DateFormat('dd/MM/yyyy').format(ctx.eventAt!)

            : '');

    final titulo = ctx.eventTitle.isNotEmpty ? ctx.eventTitle : 'Compromisso';

    final titleDetail = _compactTitleDetail(titulo);

    final title = titleDetail.isEmpty || titleDetail == 'Compromisso'
        ? _pushTitle(ctx.leadMin, 'compromisso')
        : '${leadTitlePrefix(ctx.leadMin)} — Compromisso: $titleDetail';

    final greet = _greet(ctx.userName);

    final lines = <String>[

      '📅 $dateStr · 🕒 $startHm',

      '📝 $titulo',

    ];

    if (ctx.cliente.isNotEmpty) lines.add('👤 Cliente: ${ctx.cliente}');

    if (ctx.local.isNotEmpty) lines.add('📍 ${ctx.local}');

    lines.add('');

    lines.add('Toque para abrir a agenda.');

    var body = lines.join('\n');

    if (greet != 'Olá') body = '$greet,\n\n$body';

    return (title: title, body: body);

  }



  static ({String title, String body}) _buildEscala(

    NotificationMessageContext ctx,

  ) {

    final day = _eventDayContext(ctx.eventAt);

    final startHm = _formatTimeHm(ctx.timeStr);

    final endHm = _formatTimeHm(ctx.endStr.isEmpty ? '18:00' : ctx.endStr);

    final dateStr = day.dateStr.isNotEmpty

        ? day.dateStr

        : (ctx.eventAt != null

            ? DateFormat('dd/MM/yyyy').format(ctx.eventAt!)

            : '');

    final escalaNome = ctx.eventTitle.isNotEmpty && ctx.eventTitle != 'Plantão'
        ? ctx.eventTitle
        : ctx.local;
    final titleDetail = _compactTitleDetail(escalaNome);

    final title = titleDetail.isEmpty || titleDetail == 'Plantão'
        ? _pushTitle(ctx.leadMin, 'escala')
        : '${leadTitlePrefix(ctx.leadMin)} — Escala: $titleDetail';

    final greet = _greet(ctx.userName);

    final lines = <String>['📅 $dateStr · 🕒 $startHm – $endHm'];

    if (ctx.eventTitle.isNotEmpty && ctx.eventTitle != 'Plantão') {

      lines.add('📝 ${ctx.eventTitle}');

    }

    if (ctx.local.isNotEmpty && ctx.local != 'Plantão') {

      lines.add('📍 ${ctx.local}');

    }

    lines.add('');

    lines.add('Toque para ver a escala.');

    var body = lines.join('\n');

    if (greet != 'Olá') body = '$greet,\n\n$body';

    return (title: title, body: body);

  }

}

