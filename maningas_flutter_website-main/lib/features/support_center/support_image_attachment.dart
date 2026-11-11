import 'dart:typed_data';

class SupportImageAttachment {
  const SupportImageAttachment({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}
