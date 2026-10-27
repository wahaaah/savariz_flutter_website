class TransactionLineItem {
  const TransactionLineItem({
    required this.name,
    this.quantity,
    this.unitPrice,
  });

  final String name;
  final int? quantity;
  final double? unitPrice;

  double? get total =>
      quantity == null || unitPrice == null ? null : quantity! * unitPrice!;

  factory TransactionLineItem.fromJson(Map<String, dynamic> json) {
    final quantity = _optionalInt(json['quantity']);
    final unitPrice = _optionalDouble(json['unit_price']);
    final name = json['item_name'];
    return TransactionLineItem(
      name: name is String && name.trim().isNotEmpty
          ? name.trim()
          : 'Unknown Item',
      quantity: quantity,
      unitPrice: unitPrice,
    );
  }
}

class TransactionRecord {
  const TransactionRecord({
    required this.reference,
    required this.description,
    required this.items,
    required this.status,
    this.dateValue,
    this.subtotal,
    this.vat,
    this.total,
    this.discountName,
    this.discountPercent,
    this.discountAmount,
  });

  factory TransactionRecord.fromJson(Map<String, dynamic> json) {
    final itemsValue = json['items'];
    if (itemsValue != null && itemsValue is! List) {
      throw const FormatException('Invalid transaction items.');
    }
    final items = <TransactionLineItem>[];
    for (final item in (itemsValue as List? ?? const [])) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid transaction item.');
      }
      items.add(TransactionLineItem.fromJson(item));
    }

    final rawDate =
        json['created_at'] ??
        json['transaction_date'] ??
        json['date'] ??
        json['paid_at'];
    final dateValue = rawDate is String && DateTime.tryParse(rawDate) != null
        ? rawDate
        : null;
    final rawDescription =
        json['purpose_of_visit'] ??
        json['description'] ??
        json['purpose'] ??
        json['category'];
    final rawStatus =
        json['payment_status'] ?? json['transaction_status'] ?? json['status'];

    return TransactionRecord(
      reference:
          _firstNonEmptyString([
            json['invoice_number'],
            json['id'],
            json['transaction_id'],
            json['reference_number'],
          ]) ??
          'Not available',
      dateValue: dateValue,
      description: rawDescription is String && rawDescription.trim().isNotEmpty
          ? rawDescription.trim()
          : 'Description unavailable',
      items: items,
      subtotal: _optionalDouble(json['subtotal'] ?? json['sub_total']),
      discountName: _optionalString(json['discount_name']),
      discountPercent: _optionalDouble(
        json['discount_percent'] ?? json['discount_percentage'],
      ),
      discountAmount: _optionalDouble(
        json['discount_amount'] ?? json['discount'],
      ),
      vat: _optionalDouble(json['vat_amount'] ?? json['vat']),
      total: _optionalDouble(
        json['total_amount'] ?? json['amount'] ?? json['total'],
      ),
      status: rawStatus is String && rawStatus.trim().isNotEmpty
          ? rawStatus.trim()
          : 'Unknown',
    );
  }

  final String reference;
  final String? dateValue;
  final String description;
  final List<TransactionLineItem> items;
  final double? subtotal;
  final double? discountAmount;
  final double? discountPercent;
  final String? discountName;
  final double? vat;
  final double? total;
  final String status;

  DateTime? get date => dateValue == null ? null : DateTime.parse(dateValue!);
}

String? _firstNonEmptyString(List<Object?> values) {
  for (final value in values) {
    if (value is! String && value is! num) continue;
    final result = '$value'.trim();
    if (result.isNotEmpty) return result;
  }
  return null;
}

String? _optionalString(Object? value) {
  if (value is! String) return null;
  return value.trim().isEmpty ? null : value.trim();
}

double? _optionalDouble(Object? value) {
  if (value == null) return null;
  final number = value is num ? value.toDouble() : double.tryParse('$value');
  if (number == null || !number.isFinite) return null;
  return number;
}

int? _optionalInt(Object? value) {
  if (value == null) return null;
  final number = value is int ? value : int.tryParse('$value');
  return number;
}
