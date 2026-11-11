import '../../core/network/api_client.dart';
import '../../core/network/api_failure.dart';
import 'support_image_attachment.dart';
import 'support_ticket.dart';

abstract interface class SupportCenterRepository {
  Future<List<SupportTicket>> getMyTickets({
    required String patientId,
    required String token,
  });

  Future<List<SupportMessage>> getMessages({
    required String patientId,
    required String token,
    required String ticketId,
  });

  Future<SupportTicket?> createTicket({
    required String patientId,
    required String token,
    required String category,
    required String subject,
    required String description,
    required String priority,
  });

  Future<void> cancelTicket({required String token, required String ticketId});

  Future<void> sendMessage({
    required String token,
    required String ticketId,
    required String message,
    SupportImageAttachment? attachment,
  });

  Future<void> markMessagesRead({
    required String token,
    required String ticketId,
  });
}

class ApiSupportCenterRepository implements SupportCenterRepository {
  const ApiSupportCenterRepository(this._apiClient);

  final ApiClient _apiClient;

  static const _basePath = '/api/patients/support';

  Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
  };

  @override
  Future<List<SupportTicket>> getMyTickets({
    required String patientId,
    required String token,
  }) async {
    final response = await _apiClient.getJsonMapOrList(
      '$_basePath/my-tickets?_=${DateTime.now().millisecondsSinceEpoch}',
      headers: _headers(token),
    );
    _ensureSuccessfulResponse(response);
    final tickets = _rows(response, const ['tickets', 'data']);
    return tickets
        .map((row) => SupportTicket.fromJson(row, patientId: patientId))
        .where((ticket) => !ticket.isPatientCancelled)
        .toList(growable: false);
  }

  @override
  Future<List<SupportMessage>> getMessages({
    required String patientId,
    required String token,
    required String ticketId,
  }) async {
    final response = await _apiClient.getJsonMapOrList(
      '$_basePath/tickets/${Uri.encodeComponent(ticketId)}/messages'
      '?_=${DateTime.now().millisecondsSinceEpoch}',
      headers: _headers(token),
    );
    _ensureSuccessfulResponse(response);
    return _rows(response, const ['messages', 'data'])
        .map((row) => SupportMessage.fromJson(row, patientId: patientId))
        .toList(growable: false);
  }

  @override
  Future<SupportTicket?> createTicket({
    required String patientId,
    required String token,
    required String category,
    required String subject,
    required String description,
    required String priority,
  }) async {
    final response = await _apiClient.postJson(
      '$_basePath/tickets',
      headers: _headers(token),
      body: {
        'category': category,
        'subject': subject,
        'description': description,
        'priority': priority,
      },
    );
    _ensureSuccessfulResponse(response);
    final created = response['ticket'] ?? response['data'] ?? response;
    if (created is! Map<String, dynamic> || _ticketId(created) == null) {
      return null;
    }
    return SupportTicket.fromJson(created, patientId: patientId);
  }

  @override
  Future<void> cancelTicket({
    required String token,
    required String ticketId,
  }) async {
    final response = await _apiClient.putJson(
      '$_basePath/tickets/${Uri.encodeComponent(ticketId)}/cancel',
      headers: _headers(token),
    );
    _ensureSuccessfulResponse(response);
  }

  @override
  Future<void> sendMessage({
    required String token,
    required String ticketId,
    required String message,
    SupportImageAttachment? attachment,
  }) async {
    final path = '$_basePath/tickets/${Uri.encodeComponent(ticketId)}/messages';
    final response = attachment == null
        ? await _apiClient.postJson(
            path,
            headers: _headers(token),
            body: {'message': message},
          )
        : await _apiClient.postMultipart(
            path,
            headers: _headers(token),
            fields: {'message': message},
            fileField: 'image',
            fileName: attachment.fileName,
            fileMimeType: attachment.mimeType,
            fileBytes: attachment.bytes,
          );
    _ensureSuccessfulResponse(response);
  }

  @override
  Future<void> markMessagesRead({
    required String token,
    required String ticketId,
  }) async {
    final response = await _apiClient.putJson(
      '$_basePath/tickets/${Uri.encodeComponent(ticketId)}/messages/read',
      headers: _headers(token),
    );
    _ensureSuccessfulResponse(response);
  }
}

void _ensureSuccessfulResponse(Object response) {
  if (response is Map<String, dynamic> && response['success'] == false) {
    final message = response['message'] ?? response['error'];
    throw ApiFailure(
      kind: ApiFailureKind.http,
      message: message is String && message.trim().isNotEmpty
          ? message.trim()
          : 'The support request could not be completed.',
    );
  }
}

List<Map<String, dynamic>> _rows(Object response, List<String> keys) {
  final values = switch (response) {
    List<Object?> list => list,
    Map<String, dynamic> body => _listFromBody(body, keys),
    _ => throw const FormatException('Invalid support response.'),
  };
  return values
      .map((value) {
        if (value is! Map<String, dynamic>) {
          throw const FormatException('Invalid support record.');
        }
        return value;
      })
      .toList(growable: false);
}

List<Object?> _listFromBody(Map<String, dynamic> body, List<String> keys) {
  for (final key in keys) {
    final value = body[key];
    if (value is List<Object?>) return value;
  }
  throw const FormatException('Invalid support response.');
}

String? _ticketId(Map<String, dynamic> ticket) {
  for (final key in const ['id', 'ticket_id', 'ticketId']) {
    final value = ticket[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num) return value.toString();
  }
  return null;
}
