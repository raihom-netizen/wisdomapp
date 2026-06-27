export 'course_video_embed_stub.dart'
    if (dart.library.html) 'course_video_embed_web.dart'
    if (dart.library.io) 'course_video_embed_mobile.dart';
