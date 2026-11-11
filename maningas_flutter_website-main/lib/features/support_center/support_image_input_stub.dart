import 'support_image_attachment.dart';

class SupportImageInput {
  SupportImageInput({
    required bool Function() canPaste,
    required void Function(SupportImageAttachment image) onImage,
    required void Function(String message) onError,
  });

  Future<SupportImageAttachment?> pickImage() async => null;

  void dispose() {}
}
