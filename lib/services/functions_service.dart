import 'package:cloud_functions/cloud_functions.dart';
import 'dart:convert';
class FunctionsService {
  /// Mesma região das Cloud Functions em `functions/index.js` (ex.: mpWebhook, ctCreateMpPixPayment).
  final FirebaseFunctions _fn = FirebaseFunctions.instanceFor(region: 'us-central1');

  Future<Map<String, dynamic>> createCheckout({required String plan, String? promoId}) async {
    final res = await _fn.httpsCallable('ctCreateMpCheckout').call({
      'plan': plan,
      if (promoId != null && promoId.trim().isNotEmpty) 'promoId': promoId.trim(),
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Cria pagamento PIX e retorna código copia e cola (não abre Mercado Pago).
  Future<Map<String, dynamic>> createPixPayment({required String plan, String? promoId}) async {
    final res = await _fn.httpsCallable('ctCreateMpPixPayment').call({
      'plan': plan,
      if (promoId != null && promoId.trim().isNotEmpty) 'promoId': promoId.trim(),
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Valida recibo iOS com a Apple (verifyReceipt) e atualiza licença no Firestore. Legado / clientes que ainda usam IAP.
  Future<Map<String, dynamic>> verifyIosReceipt({required String receiptData}) async {
    final res = await _fn.httpsCallable('ctVerifyIosReceipt').call({
      'receiptData': receiptData,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Verifica status do PIX pendente do usuário (chamado ao abrir o app).
  Future<Map<String, dynamic>> checkMyPayment() async {
    final res = await _fn
        .httpsCallable(
          'ctCheckMyPayment',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 8)),
        )
        .call<Map<String, dynamic>>({});
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Sincroniza todos os pagamentos das últimas 24h (libera licenças quando webhook falhou). Apenas admin.
  Future<Map<String, dynamic>> syncAllMpPayments() async {
    final res = await _fn.httpsCallable('ctSyncAllMpPayments').call<Map<String, dynamic>>({});
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Sincroniza manualmente um pagamento do Mercado Pago (quando o webhook não disparou). Apenas admin.
  Future<Map<String, dynamic>> syncMpPayment({required String paymentId}) async {
    final res = await _fn.httpsCallable('ctSyncMpPayment').call({'paymentId': paymentId});
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Sincroniza pagamento PIX pelo e-mail do usuário (usa o PIX pendente salvo). Apenas admin.
  Future<Map<String, dynamic>> syncMpPaymentByEmail({required String email}) async {
    final res = await _fn.httpsCallable('ctSyncMpPaymentByEmail').call({'email': email.trim().toLowerCase()});
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Pluggy / Open Finance: connect token (URL segura). Implementação real na Cloud Function com API key no servidor.
  Future<Map<String, dynamic>> createPluggyConnectToken({String? redirectUri}) async {
    final res = await _fn.httpsCallable('ctCreatePluggyConnectToken').call({
      if (redirectUri != null && redirectUri.trim().isNotEmpty) 'redirectUri': redirectUri.trim(),
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<int> deleteScalesByRange({
    required String fromISO,
    required String toISO,
    bool dryRun = false,
  }) async {
    final res = await _fn.httpsCallable('ctDeleteScalesByRange').call({
      'fromISO': fromISO,
      'toISO': toISO,
      'dryRun': dryRun,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    return (data['deleted'] ?? data['count'] ?? 0) as int;
  }

  /// Painel Admin: grava app_config/version via Cloud Function (Admin SDK).
  Future<Map<String, dynamic>> adminPushAppVersion({
    required String version,
    required int buildNumber,
    required int versionCode,
    required String releaseTag,
    bool forceUpdate = true,
    String? apkDownloadUrl,
    String? testFlightUrl,
  }) async {
    final res = await _fn.httpsCallable('ctAdminPushAppVersion').call<Map<String, dynamic>>({
      'version': version,
      'buildNumber': buildNumber,
      'versionCode': versionCode,
      'releaseTag': releaseTag,
      'forceUpdate': forceUpdate,
      if (apkDownloadUrl != null && apkDownloadUrl.trim().isNotEmpty)
        'apkDownloadUrl': apkDownloadUrl.trim(),
      if (testFlightUrl != null && testFlightUrl.trim().isNotEmpty)
        'testFlightUrl': testFlightUrl.trim(),
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> adminUpsertCourseVideo({
    required String docId,
    required Map<String, dynamic> data,
    bool create = false,
    bool merge = true,
  }) async {
    final res = await _fn.httpsCallable('ctAdminUpsertCourseVideo').call<Map<String, dynamic>>({
      'docId': docId,
      'data': data,
      'create': create,
      'merge': merge,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> adminDeleteCourseVideos({
    required List<String> docIds,
  }) async {
    final res = await _fn.httpsCallable('ctAdminDeleteCourseVideos').call<Map<String, dynamic>>({
      'docIds': docIds,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> adminSaveWisdomCoursesModuleConfig({
    required Map<String, dynamic> data,
  }) async {
    final res = await _fn
        .httpsCallable('ctAdminSaveWisdomCoursesModuleConfig')
        .call<Map<String, dynamic>>({'data': data});
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> uploadReceiptToStorage({
    required String txPath, // ex: users_uid/<uid>/transactions/<id>
    required String filename,
    required List<int> bytes,
    required String mimeType,
  }) async {
    final b64 = base64Encode(bytes);
    final res = await _fn.httpsCallable('ctUploadReceiptToStorage').call({
      'txPath': txPath,
      'filename': filename,
      'mimeType': mimeType,
      'base64': b64,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Testa a conexão com o Google Drive (admin). Cria um arquivo de teste na pasta configurada.
  Future<Map<String, dynamic>> testBackupToDrive() async {
    final res = await _fn.httpsCallable('ctTestBackupToDrive').call<Map<String, dynamic>>({});
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Cria backup completo no Firebase Storage (admin).
  Future<Map<String, dynamic>> createFirebaseBackup() async {
    final res = await _fn.httpsCallable('ctCreateFirebaseBackup').call<Map<String, dynamic>>({});
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Lista backups no Firebase Storage (admin).
  Future<Map<String, dynamic>> listFirebaseBackups() async {
    final res = await _fn.httpsCallable('ctListFirebaseBackups').call<Map<String, dynamic>>({});
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Retorna URL assinada para download do backup (admin).
  Future<Map<String, dynamic>> getFirebaseBackupDownloadUrl({required String path}) async {
    final res = await _fn.httpsCallable('ctGetFirebaseBackupDownloadUrl').call<Map<String, dynamic>>({'path': path});
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Migração premium admin: transferir dados de um e-mail para outro (licença, lançamentos, Storage…).
  Future<Map<String, dynamic>> migrateUserEmailPremium({
    required Map<String, dynamic> payload,
  }) async {
    final res = await _fn
        .httpsCallable(
      'ctMigrateUserEmailPremium',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 540)),
    )
        .call<Map<String, dynamic>>(payload);
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Restaura backup do Firebase Storage para o Firestore (admin).
  Future<Map<String, dynamic>> restoreFirebaseBackup({required String path}) async {
    final res = await _fn.httpsCallable('ctRestoreFirebaseBackup').call<Map<String, dynamic>>({'path': path});
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Protótipo: PDF gerado no servidor (PDFKit) — amostra de lançamentos; base para export pesado sem travar o browser.
  Future<Map<String, dynamic>> financePdfPrototype() async {
    final res = await _fn
        .httpsCallable(
      'ctFinancePdfPrototype',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
    )
        .call<Map<String, dynamic>>({});
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Relatório financeiro pesado no servidor (Cloud Functions + Storage).
  /// Evita travar Web/Android quando há muitos lançamentos.
  Future<Map<String, dynamic>> generateFinancePdfServer({
    required DateTime from,
    required DateTime to,
    String? financeAccountId,
  }) async {
    final res = await _fn
        .httpsCallable(
      'ctGenerateFinancePdfServer',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 540)),
    )
        .call<Map<String, dynamic>>({
      'fromISO': DateTime(from.year, from.month, from.day).toIso8601String(),
      'toISO': DateTime(to.year, to.month, to.day, 23, 59, 59).toIso8601String(),
      if (financeAccountId != null && financeAccountId.trim().isNotEmpty)
        'financeAccountId': financeAccountId.trim(),
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Totais do período + saldo de abertura (servidor — buckets + paginação indexada).
  Future<Map<String, dynamic>> financePeriodTotals({
    required DateTime from,
    required DateTime to,
    String statusFilter = 'paid',
    String typeFilter = 'all',
  }) async {
    final res = await _fn
        .httpsCallable(
      'ctFinancePeriodTotals',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
    )
        .call<Map<String, dynamic>>({
      'fromISO': DateTime(from.year, from.month, from.day).toIso8601String(),
      'toISO': DateTime(to.year, to.month, to.day, 23, 59, 59).toIso8601String(),
      'statusFilter': statusFilter,
      'typeFilter': typeFilter,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Compromissos/lembretes num intervalo (servidor — evita stream sem filtro).
  Future<List<Map<String, dynamic>>> agendaRemindersForRange({
    required DateTime from,
    required DateTime to,
  }) async {
    final res = await _fn
        .httpsCallable(
      'ctAgendaRemindersForRange',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
    )
        .call<Map<String, dynamic>>({
      'fromISO': DateTime(from.year, from.month, from.day).toIso8601String(),
      'toISO': DateTime(to.year, to.month, to.day, 23, 59, 59).toIso8601String(),
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    final raw = data['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Cria par de lançamentos de transferência (saída + entrada) no servidor.
  Future<Map<String, dynamic>> createFinanceTransfer({
    required double amount,
    required String fromAccountId,
    required String toAccountId,
    required String fromLabel,
    required String toLabel,
    required String dateISO,
    String note = '',
  }) async {
    final res = await _fn.httpsCallable('ctFinanceCreateTransfer').call<Map<String, dynamic>>({
      'amount': amount,
      'fromAccountId': fromAccountId,
      'toAccountId': toAccountId,
      'fromLabel': fromLabel,
      'toLabel': toLabel,
      'dateISO': dateISO,
      if (note.trim().isNotEmpty) 'note': note.trim(),
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Carrega par de transferência para edição (evita query lenta no cliente).
  Future<Map<String, dynamic>> getFinanceTransferPair({required String pairId}) async {
    final res = await _fn.httpsCallable('ctFinanceGetTransferPair').call<Map<String, dynamic>>({
      'pairId': pairId,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Registra acesso ao domínio. Chamado no carregamento web (não requer auth).
  Future<Map<String, dynamic>> logDomainAccess() async {
    try {
      final res = await _fn.httpsCallable('ctLogDomainAccess').call<Map<String, dynamic>>({});
      return Map<String, dynamic>.from(res.data as Map);
    } catch (_) {
      return {};
    }
  }

  /// OCR de imagem (Google Cloud Vision, dicas pt/en). Requer login. Retorna `null` se indisponível; o cliente usa Textify.
  Future<String?> ocrImageForSmartInput({required String base64, String mimeType = 'image/jpeg'}) async {
    final res = await _fn.httpsCallable('ctOcrImageForSmartInput').call({
      'base64': base64,
      'mimeType': mimeType,
    });
    final data = res.data;
    if (data is! Map) return null;
    final m = Map<String, dynamic>.from(data);
    if (m['ok'] == true && m['text'] is String) {
      final t = (m['text'] as String).trim();
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  /// Voz: Google Cloud Speech-to-Text (pt-BR). [encoding] p.ex. `FLAC`, [sampleRateHertz] 16000. Requer login.
  Future<String?> speechToTextForSmartInput({
    required String base64,
    int sampleRateHertz = 16000,
    String encoding = 'FLAC',
  }) async {
    final res = await _fn
        .httpsCallable(
      'ctSpeechToTextForSmartInput',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 90)),
    )
        .call({
      'base64': base64,
      'sampleRateHertz': sampleRateHertz,
      'encoding': encoding,
    });
    final data = res.data;
    if (data is! Map) return null;
    final m = Map<String, dynamic>.from(data);
    if (m['ok'] == true && m['text'] is String) {
      final t = (m['text'] as String).trim();
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  /// Estatísticas de acessos ao domínio. Requer admin. Params: period (daily|weekly|monthly|yearly), dateISO.
  Future<Map<String, dynamic>> getDomainAccessStats({required String period, String? dateISO}) async {
    final res = await _fn.httpsCallable('ctGetDomainAccessStats').call<Map<String, dynamic>>({
      'period': period,
      if (dateISO != null) 'dateISO': dateISO,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> uploadBudgetPdfToStorage({
    required String budgetPath, // ex: users/<uid>/quotes/<id>
    required String filename,
    required List<int> bytes,
  }) async {
    final b64 = base64Encode(bytes);
    final res = await _fn.httpsCallable('ctUploadBudgetPdfToStorage').call({
      'budgetPath': budgetPath,
      'filename': filename,
      'base64': b64,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Gera itens de orçamento a partir do texto (IA no backend ou rascunho).
  Future<Map<String, dynamic>?> generateBudgetWithAI(String description) async {
    final res = await _fn.httpsCallable('ctGenerateBudgetWithAI').call({'text': description});
    final data = res.data;
    if (data is Map) return Map<String, dynamic>.from(data as Map);
    return null;
  }

  /// Gera título/descrição de dica financeira (Gemini no backend ou rascunho). Só admin.
  Future<Map<String, dynamic>?> generateFinancialTipWithAI({
    required String tema,
    String categoria = 'educacao',
    String tom = 'didático e motivador',
  }) async {
    final res = await _fn.httpsCallable('ctGenerateFinancialTipWithAI').call({
      'tema': tema.trim(),
      'categoria': categoria.trim(),
      'tom': tom.trim(),
    });
    final data = res.data;
    if (data is Map) return Map<String, dynamic>.from(data as Map);
    return null;
  }

  /// E-mail em massa com link do site (promoção). Só admin. [targetUids] vazio = todos (exceto admin/master).
  /// Timeout longo: a função envia em lotes (até 2000 e-mails) e o padrão do SDK (~60s) gerava [internal] no cliente.
  Future<Map<String, dynamic>> sendMaintenancePromoEmails({
    required String linkUrl,
    required String messageText,
    List<String>? targetUids,
    String? subject,
  }) async {
    final callable = _fn.httpsCallable(
      'ctSendMaintenancePromoEmails',
      options: HttpsCallableOptions(
        timeout: const Duration(seconds: 3600),
      ),
    );
    final res = await callable.call<Map<String, dynamic>>({
      'linkUrl': linkUrl.trim(),
      'messageText': messageText.trim(),
      if (targetUids != null && targetUids.isNotEmpty) 'targetUids': targetUids,
      if (subject != null && subject.trim().isNotEmpty) 'subject': subject.trim(),
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Um e-mail de teste (mesmo layout da campanha). Só admin.
  Future<Map<String, dynamic>> sendMaintenancePromoTestEmail({
    required String linkUrl,
    required String messageText,
    required String testEmail,
    String? subject,
  }) async {
    final callable = _fn.httpsCallable(
      'ctSendMaintenancePromoTestEmail',
      options: HttpsCallableOptions(
        timeout: const Duration(seconds: 120),
      ),
    );
    final res = await callable.call<Map<String, dynamic>>({
      'linkUrl': linkUrl.trim(),
      'messageText': messageText.trim(),
      'testEmail': testEmail.trim().toLowerCase(),
      if (subject != null && subject.trim().isNotEmpty) 'subject': subject.trim(),
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Importa/atualiza lista ASSEGO por e-mails (admin).
  Future<Map<String, dynamic>> upsertAssegoMembers({
    required List<String> emails,
  }) async {
    return upsertPartnershipMembers(
      partnershipId: 'assego',
      emails: emails,
      source: 'admin_csv',
    );
  }

  Future<Map<String, dynamic>> upsertPartnershipMembers({
    required String partnershipId,
    required List<String> emails,
    String source = 'admin_csv',
  }) async {
    final callable = _fn.httpsCallable(
      'ctUpsertPartnershipMembers',
      options: HttpsCallableOptions(
        timeout: const Duration(seconds: 540),
      ),
    );
    final res = await callable.call<Map<String, dynamic>>({
      'partnershipId': partnershipId,
      'emails': emails,
      'source': source,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Remove e-mails do convênio (membro inactive + usuário volta ao premium varejo quando aplicável).
  Future<Map<String, dynamic>> removeEmailsFromPartnership({
    required String partnershipId,
    required List<String> emails,
    String source = 'admin_panel',
  }) async {
    final res =
        await _fn.httpsCallable('ctRemoveEmailsFromPartnership').call<Map<String, dynamic>>({
      'partnershipId': partnershipId.trim().toLowerCase(),
      'emails': emails,
      'source': source,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Prorroga +1 ano para todos os usuários premium_assego (admin).
  Future<Map<String, dynamic>> renewAssegoLicenses({
    bool onlyActive = true,
  }) async {
    return renewPartnershipLicenses(
      partnershipId: 'assego',
      onlyActive: onlyActive,
    );
  }

  Future<Map<String, dynamic>> renewPartnershipLicenses({
    required String partnershipId,
    bool onlyActive = true,
    /// Mesmo critério das métricas: também usuários com [plan] igual ao do convênio (sem partnershipId).
    bool unionPlanMatch = false,
  }) async {
    final res = await _fn
        .httpsCallable('ctRenewPartnershipLicenses')
        .call<Map<String, dynamic>>({
      'partnershipId': partnershipId,
      'onlyActive': onlyActive,
      'unionPlanMatch': unionPlanMatch,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Associa usuários ao convênio, plano e vigência (servidor). Até 300 UIDs por chamada.
  Future<Map<String, dynamic>> bulkMigrateUsersToPartnership({
    required String partnershipId,
    required List<String> uids,
    String? planCodeOverride,
  }) async {
    final res =
        await _fn.httpsCallable('ctBulkMigrateUsersToPartnership').call<Map<String, dynamic>>({
      'partnershipId': partnershipId.trim().toLowerCase(),
      'uids': uids,
      if (planCodeOverride != null && planCodeOverride.trim().isNotEmpty)
        'planCodeOverride': planCodeOverride.trim().toLowerCase(),
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Puxa CSV da URL configurada no convênio (ou [csvUrl] informada) e atualiza membros. Só admin.
  Future<Map<String, dynamic>> syncPartnershipCsvSource({
    required String partnershipId,
    String? csvUrl,
    /// Quando true, remove do convênio quem não aparecer mais no CSV (até 5000 membros ativos lidos).
    bool removeMissingNotInCsv = false,
  }) async {
    final res = await _fn.httpsCallable('ctSyncPartnershipCsvSource').call<Map<String, dynamic>>({
      'partnershipId': partnershipId.trim().toLowerCase(),
      if (csvUrl != null && csvUrl.trim().isNotEmpty) 'csvUrl': csvUrl.trim(),
      if (removeMissingNotInCsv) 'removeMissingNotInCsv': true,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Importa membros a partir do conteúdo do CSV enviado pelo painel admin (upload manual). Só admin.
  Future<Map<String, dynamic>> importPartnershipCsvManual({
    required String partnershipId,
    required String csvText,
    bool removeMissingNotInCsv = false,
  }) async {
    final res =
        await _fn.httpsCallable('ctImportPartnershipCsvManual').call<Map<String, dynamic>>({
      'partnershipId': partnershipId.trim().toLowerCase(),
      'csvText': csvText,
      if (removeMissingNotInCsv) 'removeMissingNotInCsv': true,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> createOrUpdatePartnership({
    required String id,
    required String name,
    required String slug,
    required int durationDays,
    String planCode = 'premium_assego',
    bool active = true,
    bool autoApplyOnSignup = true,
    /// `yyyy-MM-DD` ou string vazia para remover (apenas se enviar chave).
    String? contractStartsAtIso,
    String? contractEndsAtIso,
    /// Dias extras na licença após [contractEndsAt] (renovação em atraso). Só envie se quiser gravar.
    int? licenseRenewalExtensionDays,
  }) async {
    final payload = <String, dynamic>{
      'id': id,
      'name': name,
      'slug': slug,
      'durationDays': durationDays,
      'planCode': planCode,
      'active': active,
      'autoApplyOnSignup': autoApplyOnSignup,
    };
    if (contractStartsAtIso != null) {
      payload['contractStartsAt'] = contractStartsAtIso;
    }
    if (contractEndsAtIso != null) {
      payload['contractEndsAt'] = contractEndsAtIso;
    }
    if (licenseRenewalExtensionDays != null) {
      payload['licenseRenewalExtensionDays'] = licenseRenewalExtensionDays;
    }
    final res = await _fn
        .httpsCallable('ctCreateOrUpdatePartnership')
        .call<Map<String, dynamic>>(payload);
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Cadastro público da ASSEGO (sem login), com aplicação automática no convênio.
  Future<Map<String, dynamic>> publicAssegoSignup({
    required String name,
    required String email,
    String phone = '',
    String cpf = '',
    String notes = '',
  }) async {
    final callable = _fn.httpsCallable('ctPublicAssegoSignup');
    final res = await callable.call<Map<String, dynamic>>({
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      'phone': phone.trim(),
      'cpf': cpf.trim(),
      'notes': notes.trim(),
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Cadastro público de convênio por ID (slug), sem login.
  Future<Map<String, dynamic>> publicPartnershipSignup({
    required String partnershipId,
    required String name,
    required String email,
    String phone = '',
    String cpf = '',
    String notes = '',
  }) async {
    final callable = _fn.httpsCallable('ctPublicPartnershipSignup');
    final res = await callable.call<Map<String, dynamic>>({
      'partnershipId': partnershipId.trim().toLowerCase(),
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      'phone': phone.trim(),
      'cpf': cpf.trim(),
      'notes': notes.trim(),
    });
    return Map<String, dynamic>.from(res.data as Map);
  }
}

