import 'package:cloud_firestore/cloud_firestore.dart';

/// Stub para web: notificações locais não disponíveis.
class ScaleNotificationsService {
  static final ScaleNotificationsService _instance = ScaleNotificationsService._();
  factory ScaleNotificationsService() => _instance;
  ScaleNotificationsService._();

  bool get isSupported => false;

  Future<void> init() async {}

  Future<void> beginRescheduleBatch() async {}

  Future<void> scheduleAgendaBatch({
    required String uid,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> reminders,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> scales,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> transactions,
    DateTime? forwardCutoff,
    String? userDisplayName,
  }) async {}

  Future<void> scheduleFromScales(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {String? uid}) async {}

  Future<void> scheduleFromReminders(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {String? uid}) async {}

  Future<void> scheduleFinancialReminders(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {String? uid}) async {}

  Future<void> cancelAllScaleReminders() async {}

  Future<void> updateChannelShowAsPopup(bool showAsPopup) async {}

  Future<void> refreshChannelsAfterSoundChange() async {}

  void checkDueNow() {}

  /// Push FCM em foreground — stub (só mobile nativo).
  Future<void> showFcmPushNotification({
    required String title,
    required String body,
    String channelKind = 'escala',
    String? payload,
  }) async {}
}
