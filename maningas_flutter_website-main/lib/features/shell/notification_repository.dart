import '../../../core/network/api_client.dart';
import '../../../core/network/api_failure.dart';
import 'patient_notification.dart';

abstract interface class NotificationRepository {
  Future<List<PatientNotification>> getNotifications({
    required String patientId,
    required String token,
  });

  Future<int> getUnreadCount({
    required String patientId,
    required String token,
  });

  Future<void> markAsRead({required int notificationId, required String token});

  Future<void> markAllAsRead({
    required String patientId,
    required String token,
  });
}

class ApiNotificationRepository implements NotificationRepository {
  const ApiNotificationRepository(this._apiClient);

  final ApiClient _apiClient;

  Map<String, String> _authHeaders(String token) => {
    'Authorization': 'Bearer $token',
  };

  String _patientPath(String patientId) =>
      '/api/notifications/patient/${Uri.encodeComponent(patientId)}';

  @override
  Future<List<PatientNotification>> getNotifications({
    required String patientId,
    required String token,
  }) async {
    try {
      final rows = await _apiClient.getJsonList(
        _patientPath(patientId),
        headers: _authHeaders(token),
      );
      return rows
          .map((row) {
            if (row is! Map<String, dynamic>) {
              throw const FormatException('Invalid notification entry.');
            }
            return PatientNotification.fromJson(row);
          })
          .toList(growable: false);
    } on FormatException {
      throw const ApiFailure(
        kind: ApiFailureKind.invalidResponse,
        message: 'The clinic service returned invalid notifications.',
      );
    } on ApiFailure catch (failure) {
      throw _notificationFailure(failure);
    }
  }

  @override
  Future<int> getUnreadCount({
    required String patientId,
    required String token,
  }) async {
    try {
      final response = await _apiClient.getJson(
        '${_patientPath(patientId)}/unread-count',
        headers: _authHeaders(token),
      );
      final count = response['unread_count'];
      if (count is int && count >= 0) return count;
      if (count is num && count == count.toInt() && count >= 0) {
        return count.toInt();
      }
      throw const ApiFailure(
        kind: ApiFailureKind.invalidResponse,
        message: 'The clinic service returned an invalid unread count.',
      );
    } on ApiFailure catch (failure) {
      throw _notificationFailure(failure);
    }
  }

  @override
  Future<void> markAsRead({
    required int notificationId,
    required String token,
  }) async {
    try {
      final response = await _apiClient.patchJson(
        '/api/notifications/$notificationId/read',
        headers: _authHeaders(token),
      );
      if (response['success'] != true ||
          response['notification_id'] != notificationId ||
          response['is_read'] != true) {
        throw const ApiFailure(
          kind: ApiFailureKind.invalidResponse,
          message: 'The clinic service returned an invalid read confirmation.',
        );
      }
    } on ApiFailure catch (failure) {
      throw _notificationFailure(failure);
    }
  }

  @override
  Future<void> markAllAsRead({
    required String patientId,
    required String token,
  }) async {
    try {
      final response = await _apiClient.patchJson(
        '${_patientPath(patientId)}/read-all',
        headers: _authHeaders(token),
      );
      final updatedCount = response['updated_count'];
      if (response['success'] != true ||
          updatedCount is! num ||
          updatedCount < 0 ||
          updatedCount != updatedCount.toInt()) {
        throw const ApiFailure(
          kind: ApiFailureKind.invalidResponse,
          message: 'The clinic service returned an invalid read confirmation.',
        );
      }
    } on ApiFailure catch (failure) {
      throw _notificationFailure(failure);
    }
  }

  ApiFailure _notificationFailure(ApiFailure failure) {
    if (failure.statusCode == 401 || failure.statusCode == 403) {
      return ApiFailure(
        kind: failure.kind,
        statusCode: failure.statusCode,
        code: failure.code,
        message: failure.statusCode == 401
            ? 'Your patient session is invalid or expired. Please sign in again.'
            : 'Your account cannot access these notifications.',
      );
    }
    return failure;
  }
}
