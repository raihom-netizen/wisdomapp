// Exporta a implementação correta: web (PWA/atalho), io em mobile nativo, stub em outros.
export 'scale_notifications_service_stub.dart'
    if (dart.library.io) 'scale_notifications_service_io.dart'
    if (dart.library.html) 'scale_notifications_service_web.dart';
