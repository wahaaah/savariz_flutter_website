class CatalogFrame {
  const CatalogFrame({
    required this.frameId,
    required this.name,
    required this.price,
    required this.stockQuantity,
    this.brand,
    this.category,
    this.description,
    this.imageUrl,
    this.conversionStatus,
    this.model3dUrl,
    this.createdAt,
  });

  final int frameId;
  final String name;
  final String? brand;
  final String? category;
  final double price;
  final int stockQuantity;
  final String? description;
  final Uri? imageUrl;
  final String? conversionStatus;
  final String? model3dUrl;
  final DateTime? createdAt;

  String get availability {
    if (stockQuantity <= 0) return 'Out of Stock';
    if (stockQuantity <= 2) return 'Low Stock';
    return 'Available';
  }

  bool get isTryOnConverted => conversionStatus?.toLowerCase() == 'converted';

  bool get hasTryOnModel => isTryOnConverted && _isUsableModelUrl(model3dUrl);

  factory CatalogFrame.fromJson(
    Map<String, dynamic> json, {
    required Uri assetBaseUri,
  }) {
    final frameId = _integer(json['frame_id'], 'frame_id');
    if (frameId <= 0) {
      throw const FormatException('Invalid frame ID.');
    }

    final name = _requiredString(json['name'], 'name');
    final price = _price(json['price']);
    final stockQuantity = _integer(json['stock_quantity'], 'stock_quantity');
    if (stockQuantity < 0) {
      throw const FormatException('Invalid frame stock quantity.');
    }

    return CatalogFrame(
      frameId: frameId,
      name: name,
      brand: _optionalString(json['brand'], 'brand'),
      category: _optionalString(json['category'], 'category'),
      price: price,
      stockQuantity: stockQuantity,
      description: _optionalString(json['description'], 'description'),
      imageUrl: _imageUri(
        _firstImageUrl(json['image_2d_url'], json['image_url']),
        assetBaseUri,
      ),
      conversionStatus: _optionalString(
        json['conversion_status'],
        'conversion_status',
      ),
      model3dUrl: _optionalString(json['model_3d_url'], '3D model URL'),
      createdAt: _createdAt(json['created_at']),
    );
  }
}

bool _isUsableModelUrl(String? value) {
  if (value == null) return false;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.userInfo.isNotEmpty) return false;
  if (uri.hasScheme) {
    return uri.scheme == 'https' && uri.host.isNotEmpty;
  }
  return !uri.hasAuthority && uri.path.isNotEmpty;
}

Object? _firstImageUrl(Object? primary, Object? fallback) {
  if (primary == null || primary is String && primary.trim().isEmpty) {
    return fallback;
  }
  return primary;
}

int _integer(Object? value, String field) {
  final parsed = switch (value) {
    int number => number,
    num number when number.isFinite && number == number.roundToDouble() =>
      number.toInt(),
    String text => int.tryParse(text.trim()),
    _ => null,
  };
  if (parsed == null) {
    throw FormatException('Invalid frame $field.');
  }
  return parsed;
}

String _requiredString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid frame $field.');
  }
  return value.trim();
}

String? _optionalString(Object? value, String field) {
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('Invalid frame $field.');
  }
  final text = value.trim();
  return text.isEmpty ? null : text;
}

double _price(Object? value) {
  final parsed = switch (value) {
    num number => number.toDouble(),
    String text => double.tryParse(text.trim()),
    _ => null,
  };
  if (parsed == null || !parsed.isFinite || parsed < 0) {
    throw const FormatException('Invalid frame price.');
  }
  return parsed;
}

Uri? _imageUri(Object? value, Uri assetBaseUri) {
  final path = _optionalString(value, 'image URL');
  if (path == null) return null;

  final parsed = Uri.tryParse(path);
  if (parsed == null || parsed.hasAuthority && !parsed.hasScheme) {
    throw const FormatException('Invalid frame image URL.');
  }

  final resolved = parsed.hasScheme ? parsed : assetBaseUri.resolveUri(parsed);
  final isLocalHttp =
      resolved.scheme == 'http' &&
      const {'localhost', '127.0.0.1', '::1'}.contains(resolved.host);
  if ((resolved.scheme != 'https' && !isLocalHttp) ||
      resolved.userInfo.isNotEmpty ||
      resolved.host.isEmpty) {
    throw const FormatException('Invalid frame image URL.');
  }
  return resolved;
}

DateTime? _createdAt(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw const FormatException('Invalid frame creation date.');
  }
  final text = value.trim();
  if (text.isEmpty) return null;
  final date = DateTime.tryParse(text);
  if (date == null) {
    throw const FormatException('Invalid frame creation date.');
  }
  return date;
}
