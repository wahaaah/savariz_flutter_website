import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:patient_portal_flutter/core/network/api_client.dart';
import 'package:patient_portal_flutter/features/appointment_history/appointment_history_repository.dart';

void main() {
  test('loads availability and clinic closures from the API', () async {
    final repository = ApiAppointmentHistoryRepository(
      ApiClient(
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer test-token');
          return switch (request.url.path) {
            '/api/appointments' => http.Response(
              jsonEncode({
                'appointments': [
                  {
                    'appointment_id': 10,
                    'appointment_date': '2026-11-02',
                    'appointment_time': '09:30:00',
                    'appointment_status': 'Requested',
                  },
                  {
                    'appointment_id': 11,
                    'appointment_date': '2026-11-03',
                    'appointment_time': '10:00:00',
                    'appointment_status': 'Cancelled',
                  },
                ],
              }),
              200,
            ),
            '/api/clinic-closures' => http.Response(
              jsonEncode({
                'closures': [
                  {
                    'start_date': '2026-11-05',
                    'end_date': '2026-11-06',
                    'closure_reason': 'Clinic maintenance',
                  },
                ],
              }),
              200,
            ),
            _ => http.Response('{}', 404),
          };
        }),
        baseUri: Uri.parse('https://api.example.test'),
      ),
    );

    final schedule = await repository.getBookingSchedule(token: 'test-token');

    expect(schedule.bookings, hasLength(2));
    expect(schedule.bookings.first.appointmentTime, '09:30');
    expect(schedule.bookings.first.status, 'Requested');
    expect(schedule.closures, hasLength(1));
    expect(schedule.closures.single.reason, 'Clinic maintenance');
    expect(schedule.closures.single.includes(DateTime(2026, 11, 6)), isTrue);
  });

  test('creates an appointment using the HTML API payload', () async {
    final repository = ApiAppointmentHistoryRepository(
      ApiClient(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/appointments');
          expect(request.headers['Authorization'], 'Bearer test-token');
          expect(jsonDecode(request.body), {
            'patient_id': 'patient-7',
            'appointment_date': '2026-11-02',
            'appointment_time': '09:30:00',
            'purpose_of_visit': 'Eye Examination',
            'appointment_status': 'Requested',
            'appointment_source': 'website',
          });
          return http.Response(
            jsonEncode({
              'success': true,
              'message': 'Appointment request submitted.',
            }),
            201,
          );
        }),
        baseUri: Uri.parse('https://api.example.test'),
      ),
    );

    final message = await repository.createAppointment(
      patientId: 'patient-7',
      token: 'test-token',
      date: DateTime(2026, 11, 2),
      time: '09:30:00',
      purpose: 'Eye Examination',
    );

    expect(message, 'Appointment request submitted.');
  });

  test('cancels an appointment using the HTML API route and body', () async {
    final repository = ApiAppointmentHistoryRepository(
      ApiClient(
        client: MockClient((request) async {
          expect(request.method, 'PATCH');
          expect(
            request.url.path,
            '/api/appointments/patient/appointment%2F9/cancel',
          );
          expect(request.headers['Authorization'], 'Bearer test-token');
          expect(jsonDecode(request.body), {'patient_id': 'patient-7'});
          return http.Response(
            jsonEncode({'success': true, 'message': 'Appointment cancelled.'}),
            200,
          );
        }),
        baseUri: Uri.parse('https://api.example.test'),
      ),
    );

    final message = await repository.cancelAppointment(
      patientId: 'patient-7',
      token: 'test-token',
      appointmentId: 'appointment/9',
    );

    expect(message, 'Appointment cancelled.');
  });
}
