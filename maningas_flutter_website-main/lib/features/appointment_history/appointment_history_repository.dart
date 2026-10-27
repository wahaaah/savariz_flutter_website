import '../../../core/network/api_client.dart';
import '../../../core/network/api_failure.dart';
import '../appointments/booking_schedule.dart';
import 'appointment_history_record.dart';

abstract interface class AppointmentHistoryRepository {
  Future<List<AppointmentHistoryRecord>> getAppointments({
    required String patientId,
    required String token,
  });

  Future<BookingSchedule> getBookingSchedule({required String token});

  Future<String> createAppointment({
    required String patientId,
    required String token,
    required DateTime date,
    required String time,
    required String purpose,
  });

  Future<String> cancelAppointment({
    required String patientId,
    required String token,
    required String appointmentId,
  });
}

class ApiAppointmentHistoryRepository implements AppointmentHistoryRepository {
  const ApiAppointmentHistoryRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<AppointmentHistoryRecord>> getAppointments({
    required String patientId,
    required String token,
  }) async {
    try {
      final response = await _apiClient.getJsonMapOrList(
        '/api/appointments/patient/${Uri.encodeComponent(patientId)}',
        headers: {'Authorization': 'Bearer $token'},
      );
      final rows = switch (response) {
        List<Object?> values => values,
        Map<String, dynamic> body
            when body['appointments'] is List<Object?> =>
          body['appointments'] as List<Object?>,
        Map<String, dynamic> body when body['data'] is List<Object?> =>
          body['data'] as List<Object?>,
        _ => throw const FormatException('Invalid appointment response.'),
      };
      return rows
          .map((row) {
            if (row is! Map<String, dynamic>) {
              throw const FormatException('Invalid appointment record.');
            }
            return PatientAppointment.fromJson(row);
          })
          .toList(growable: false);
    } on FormatException {
      throw const ApiFailure(
        kind: ApiFailureKind.invalidResponse,
        message: 'The clinic service returned invalid appointment history.',
      );
    } on ApiFailure catch (failure) {
      if (failure.statusCode == 401 || failure.statusCode == 403) {
        throw ApiFailure(
          kind: failure.kind,
          statusCode: failure.statusCode,
          code: failure.code,
          message: failure.statusCode == 401
              ? 'Your patient session is invalid or expired. Please sign in again.'
              : 'Your account cannot access appointment history.',
        );
      }
      rethrow;
    }
  }

  @override
  Future<BookingSchedule> getBookingSchedule({required String token}) async {
    try {
      final responses = await Future.wait<Object>([
        _apiClient.getJsonMapOrList(
          '/api/appointments',
          headers: _authHeaders(token),
        ),
        _apiClient.getJsonMapOrList(
          '/api/clinic-closures',
          headers: _authHeaders(token),
        ),
      ]);
      final bookings = _responseRows(
        responses[0],
        const ['appointments', 'data'],
      ).map((row) {
        if (row is! Map<String, dynamic>) {
          throw const FormatException('Invalid appointment availability row.');
        }
        final appointment = PatientAppointment.fromJson(row);
        final date = appointment.date;
        final time = appointment.time;
        if (date == null || time == null) {
          throw const FormatException(
            'Appointment availability is missing date or time.',
          );
        }
        return AppointmentBooking(
          appointmentDate: date,
          appointmentTime: time,
          status: appointment.status,
        );
      }).toList(growable: false);
      final closures = _responseRows(
        responses[1],
        const ['closures', 'data'],
      ).map((row) {
        if (row is! Map<String, dynamic>) {
          throw const FormatException('Invalid clinic closure row.');
        }
        final start = _dateValue(row['start_date']);
        final end = _dateValue(row['end_date']);
        if (start == null || end == null || end.isBefore(start)) {
          throw const FormatException('Invalid clinic closure date range.');
        }
        return ClinicClosure(
          startDate: start,
          endDate: end,
          reason: _firstString(row, const [
            'reason',
            'closure_reason',
            'description',
          ]),
        );
      }).toList(growable: false);
      return BookingSchedule(bookings: bookings, closures: closures);
    } on FormatException {
      throw const ApiFailure(
        kind: ApiFailureKind.invalidResponse,
        message: 'The clinic service returned invalid booking availability.',
      );
    } on ApiFailure catch (failure) {
      throw _appointmentFailure(failure);
    }
  }

  @override
  Future<String> createAppointment({
    required String patientId,
    required String token,
    required DateTime date,
    required String time,
    required String purpose,
  }) async {
    try {
      final response = await _apiClient.postJson(
        '/api/appointments',
        headers: _authHeaders(token),
        body: {
          'patient_id': patientId,
          'appointment_date': _dateString(date),
          'appointment_time': time,
          'purpose_of_visit': purpose,
          'appointment_status': 'Requested',
          'appointment_source': 'website',
        },
      );
      if (response['success'] == false) {
        throw ApiFailure(
          kind: ApiFailureKind.http,
          message: _firstString(
            response,
            const ['error', 'message'],
            fallback: 'Unable to book appointment.',
          ),
        );
      }
      return _firstString(
        response,
        const ['message'],
        fallback: 'Appointment request submitted successfully.',
      );
    } on ApiFailure catch (failure) {
      throw _appointmentFailure(failure);
    }
  }

  @override
  Future<String> cancelAppointment({
    required String patientId,
    required String token,
    required String appointmentId,
  }) async {
    try {
      final response = await _apiClient.patchJson(
        '/api/appointments/patient/${Uri.encodeComponent(appointmentId)}/cancel',
        headers: _authHeaders(token),
        body: {'patient_id': patientId},
      );
      if (response['success'] == false) {
        throw ApiFailure(
          kind: ApiFailureKind.http,
          message: _firstString(
            response,
            const ['error', 'message'],
            fallback: 'Unable to cancel appointment.',
          ),
        );
      }
      return _firstString(
        response,
        const ['message'],
        fallback: 'Your appointment has been cancelled successfully.',
      );
    } on ApiFailure catch (failure) {
      throw _appointmentFailure(failure);
    }
  }

  Map<String, String> _authHeaders(String token) => {
    'Authorization': 'Bearer $token',
  };

  ApiFailure _appointmentFailure(ApiFailure failure) {
    if (failure.statusCode == 401 || failure.statusCode == 403) {
      return ApiFailure(
        kind: failure.kind,
        statusCode: failure.statusCode,
        code: failure.code,
        message: failure.statusCode == 401
            ? 'Your patient session is invalid or expired. Please sign in again.'
            : 'Your account cannot access appointments.',
      );
    }
    return failure;
  }
}

List<Object?> _responseRows(Object response, List<String> keys) {
  if (response is List<Object?>) return response;
  if (response is Map<String, dynamic>) {
    for (final key in keys) {
      final value = response[key];
      if (value is List<Object?>) return value;
    }
  }
  throw const FormatException('Invalid appointment response.');
}

DateTime? _dateValue(Object? value) {
  if (value is! String || value.length < 10) return null;
  final date = DateTime.tryParse(value.substring(0, 10));
  if (date == null) return null;
  return DateTime(date.year, date.month, date.day);
}

String _dateString(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _firstString(
  Map<String, dynamic> values,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = values[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return fallback;
}
