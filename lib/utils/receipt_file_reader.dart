import 'dart:typed_data';

import 'receipt_file_reader_stub.dart'
    if (dart.library.io) 'receipt_file_reader_io.dart' as impl;

Future<Uint8List?> readLocalFileBytes(String? path) =>
    impl.readLocalFileBytes(path);
