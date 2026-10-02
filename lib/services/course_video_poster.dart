/// Prévia (quadro) dos vídeos MP4 dos Cursos — capa «tipo YouTube/Instagram»
/// quando o admin não enviou capa própria.
///
/// - [courseVideoPosterFromBytes] / [courseVideoPosterFromFilePath]: gera um
///   JPEG de um quadro (~1 s) do vídeo no MOMENTO DO ENVIO (admin), que vai
///   para o Storage junto do vídeo (`poster_*.jpg`) — todos veem rápido.
/// - [courseVideoFrameImage]: vídeos antigos sem quadro gravado. Android/iOS:
///   baixa só o começo (e o índice) do MP4, extrai um quadro com o FFmpeg e
///   guarda em cache local. Web: `<video>` fora da tela (só metadados + o
///   trecho de ~1 s) desenhado num canvas — sem elemento HTML por cima do
///   Flutter (não atrapalha rolagem nem toque).
library;

export 'course_video_poster_stub.dart'
    if (dart.library.html) 'course_video_poster_web.dart'
    if (dart.library.io) 'course_video_poster_io.dart';
