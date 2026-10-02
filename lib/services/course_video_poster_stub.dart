import 'dart:typed_data';

import 'package:flutter/painting.dart';

/// Plataforma sem suporte: sem prévia gerada (a capa cai na reserva).
Future<Uint8List?> courseVideoPosterFromBytes(
  Uint8List bytes,
  String mimeType,
) async =>
    null;

Future<Uint8List?> courseVideoPosterFromFilePath(String path) async => null;

Future<ImageProvider?> courseVideoFrameImage(String videoUrl) async => null;
