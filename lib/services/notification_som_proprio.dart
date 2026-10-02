// Toque próprio (MP3/WAV/M4A/voz gravada) tocando com o app fechado.
// No app usa FFmpeg + canal nativo; na web não há o que preparar.
export 'notification_som_proprio_stub.dart'
    if (dart.library.io) 'notification_som_proprio_io.dart';
