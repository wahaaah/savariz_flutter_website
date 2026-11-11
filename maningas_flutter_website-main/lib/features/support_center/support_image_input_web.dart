import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'support_image_attachment.dart';

class SupportImageInput {
  SupportImageInput({
    required this.canPaste,
    required this.onImage,
    required this.onError,
  }) {
    _pasteListener = _handlePaste.toJS;
    _changeListener = _handleFileChange.toJS;
    _cancelListener = _handleFileCancel.toJS;
    web.document.addEventListener('paste', _pasteListener);

    _fileInput = web.document.createElement('input') as web.HTMLInputElement
      ..type = 'file'
      ..accept = 'image/*';
    _fileInput.style.display = 'none';
    _fileInput.addEventListener('change', _changeListener);
    _fileInput.addEventListener('cancel', _cancelListener);
    web.document.body?.append(_fileInput);
  }

  final bool Function() canPaste;
  final void Function(SupportImageAttachment image) onImage;
  final void Function(String message) onError;

  late final JSFunction _pasteListener;
  late final JSFunction _changeListener;
  late final JSFunction _cancelListener;
  late final web.HTMLInputElement _fileInput;
  Completer<SupportImageAttachment?>? _pickerCompleter;

  Future<SupportImageAttachment?> pickImage() {
    final existing = _pickerCompleter;
    if (existing != null) return existing.future;

    final completer = Completer<SupportImageAttachment?>();
    _pickerCompleter = completer;
    _fileInput.value = '';
    _fileInput.click();
    return completer.future;
  }

  void _handlePaste(web.Event event) {
    if (!canPaste()) return;

    final items = (event as web.ClipboardEvent).clipboardData?.items;
    if (items == null) return;
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      if (!item.type.startsWith('image/')) continue;
      final file = item.getAsFile();
      if (file == null) continue;

      event.preventDefault();
      _readImage(file).then<void>(
        onImage,
        onError: (Object error, StackTrace stackTrace) {
          onError(_errorMessage(error));
        },
      );
      return;
    }
  }

  void _handleFileChange(web.Event event) {
    final completer = _pickerCompleter;
    if (completer == null || completer.isCompleted) return;
    _pickerCompleter = null;
    final file = _fileInput.files?.item(0);
    if (file == null) {
      completer.complete(null);
      return;
    }
    _readImage(file).then<void>(
      completer.complete,
      onError: (Object error, StackTrace stackTrace) {
        completer.completeError(error, stackTrace);
      },
    );
  }

  void _handleFileCancel(web.Event event) {
    final completer = _pickerCompleter;
    _pickerCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete(null);
  }

  Future<SupportImageAttachment> _readImage(web.File file) async {
    final mimeType = file.type;
    if (!mimeType.startsWith('image/')) {
      throw const FormatException('Please select a valid image file.');
    }

    final reader = web.FileReader();
    final result = Completer<String>();
    final loadListener = ((web.Event event) {
      final value = reader.result;
      if (value != null && value.isA<JSString>()) {
        result.complete((value as JSString).toDart);
      } else {
        result.completeError(
          StateError('The selected image could not be read.'),
        );
      }
    }).toJS;
    final errorListener = ((web.Event event) {
      result.completeError(StateError('The selected image could not be read.'));
    }).toJS;
    reader.addEventListener('load', loadListener);
    reader.addEventListener('error', errorListener);
    reader.readAsDataURL(file);

    final dataUrl = await result.future;
    final separator = dataUrl.indexOf(',');
    if (separator < 0) {
      throw const FormatException('The selected image has an invalid format.');
    }
    final bytes = Uint8List.fromList(
      base64.decode(dataUrl.substring(separator + 1)),
    );
    if (bytes.isEmpty) {
      throw const FormatException('The selected image is empty.');
    }

    return SupportImageAttachment(
      bytes: bytes,
      fileName: file.name.isNotEmpty ? file.name : _fallbackName(mimeType),
      mimeType: mimeType,
    );
  }

  String _fallbackName(String mimeType) {
    final subtype = mimeType.split('/').last.toLowerCase();
    final extension = switch (subtype) {
      'jpeg' => 'jpg',
      'svg+xml' => 'svg',
      'webp' => 'webp',
      'gif' => 'gif',
      _ => 'png',
    };
    return 'pasted-image.$extension';
  }

  String _errorMessage(Object error) => switch (error) {
    FormatException exception => exception.message,
    StateError exception => exception.message,
    _ => 'The selected image could not be read.',
  };

  void dispose() {
    web.document.removeEventListener('paste', _pasteListener);
    _fileInput.removeEventListener('change', _changeListener);
    _fileInput.removeEventListener('cancel', _cancelListener);
    _fileInput.remove();
    final completer = _pickerCompleter;
    _pickerCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete(null);
  }
}
