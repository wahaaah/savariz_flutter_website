class SupportMessage {
  const SupportMessage({
    required this.body,
    required this.senderName,
    required this.sentAt,
    required this.isMine,
  });

  final String body;
  final String senderName;
  final DateTime? sentAt;
  final bool isMine;

  factory SupportMessage.fromJson(
    Map<String, dynamic> json, {
    required String patientId,
  }) {
    final senderType = _stringValue(json, const ['sender_type'])?.toLowerCase();
    final senderPatientId = _stringValue(json, const ['sender_patient_id']);
    final isMine =
        senderType == 'patient' &&
        senderPatientId != null &&
        senderPatientId == patientId;
    return SupportMessage(
      body: _stringValue(json, const ['message', 'content', 'body']) ?? '',
      senderName:
          _stringValue(json, const ['sender_name', 'senderName']) ??
          (isMine ? 'You' : 'Clinic Support'),
      sentAt: _dateValue(json, const [
        'created_at',
        'createdAt',
        'sent_at',
      ]),
      isMine: isMine,
    );
  }
}

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.subject,
    required this.category,
    required this.status,
    required this.priority,
    required this.updatedAt,
    required this.messages,
    this.isPatientCancelled = false,
  });

  final String id;
  final String subject;
  final String category;
  final String status;
  final String priority;
  final DateTime? updatedAt;
  final List<SupportMessage> messages;
  final bool isPatientCancelled;

  SupportTicket withMessages(List<SupportMessage> value) => SupportTicket(
    id: id,
    subject: subject,
    category: category,
    status: status,
    priority: priority,
    updatedAt: updatedAt,
    messages: value,
    isPatientCancelled: isPatientCancelled,
  );

  factory SupportTicket.fromJson(
    Map<String, dynamic> json, {
    required String patientId,
  }) {
    final id = _stringValue(json, const ['id', 'ticket_id', 'ticketId']);
    if (id == null || id.isEmpty) {
      throw const FormatException('Support ticket is missing its ID.');
    }
    final status = _stringValue(json, const ['status']) ?? 'Open';
    final resolution = (_stringValue(json, const [
      'resolution',
      'resolution_note',
      'cancellation_reason',
      'close_reason',
    ]) ?? '').trim().toLowerCase();
    final rawMessages = json['messages'];
    final messages = rawMessages is List<Object?>
        ? rawMessages
              .whereType<Map<String, dynamic>>()
              .map(
                (message) => SupportMessage.fromJson(
                  message,
                  patientId: patientId,
                ),
              )
              .toList(growable: false)
        : const <SupportMessage>[];
    return SupportTicket(
      id: id,
      subject: _stringValue(json, const ['subject']) ?? '',
      category: _stringValue(json, const ['category']) ?? 'General',
      status: status,
      priority: _stringValue(json, const ['priority']) ?? 'Medium',
      updatedAt: _dateValue(json, const [
        'updated_at',
        'updatedAt',
        'created_at',
        'createdAt',
      ]),
      messages: messages,
      isPatientCancelled:
          status.trim().toLowerCase() == 'cancelled' ||
          resolution == 'cancelled' ||
          resolution == 'cancelled by patient',
    );
  }
}

abstract final class SupportTicketOptions {
  static const categories = [
    'Appointment',
    'Billing / Payment',
    'Patient Account',
    'Eyewear / Frames',
    'Website / Technical Issue',
    'General Inquiry',
    'Other',
  ];

  static const priorities = ['Low', 'Medium', 'High', 'Urgent'];
}

String? _stringValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num) return value.toString();
  }
  return null;
}

DateTime? _dateValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return null;
}
