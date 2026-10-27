class PatientNotification {
  const PatientNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.isRead,
    this.createdAt,
  });

  factory PatientNotification.fromJson(Map<String, dynamic> json) {
    final rawId = json['notification_id'];
    final id = rawId is int
        ? rawId
        : rawId is num && rawId == rawId.toInt()
        ? rawId.toInt()
        : rawId is String
        ? int.tryParse(rawId)
        : null;
    final rawTitle = json['title'];
    final rawBody = json['body'];
    final rawRead = json['is_read'];
    final rawCreatedAt = json['created_at'];
    final isRead = rawRead == true || rawRead == 1 || rawRead == '1';

    if (id == null ||
        id <= 0 ||
        rawTitle != null && rawTitle is! String ||
        rawBody != null && rawBody is! String ||
        rawRead != true &&
            rawRead != false &&
            rawRead != 0 &&
            rawRead != 1 &&
            rawRead != '0' &&
            rawRead != '1' ||
        rawCreatedAt != null && rawCreatedAt is! String) {
      throw const FormatException('Invalid notification entry.');
    }

    final createdAt = rawCreatedAt == null
        ? null
        : DateTime.tryParse(rawCreatedAt as String);
    if (rawCreatedAt != null && createdAt == null) {
      throw const FormatException('Invalid notification timestamp.');
    }

    return PatientNotification(
      id: id,
      title: (rawTitle as String?)?.trim().isNotEmpty == true
          ? (rawTitle as String).trim()
          : 'Notification',
      body: (rawBody as String?)?.trim() ?? '',
      isRead: isRead,
      createdAt: createdAt,
    );
  }

  final int id;
  final String title;
  final String body;
  final bool isRead;
  final DateTime? createdAt;

  PatientNotification copyWith({bool? isRead}) => PatientNotification(
    id: id,
    title: title,
    body: body,
    isRead: isRead ?? this.isRead,
    createdAt: createdAt,
  );
}
