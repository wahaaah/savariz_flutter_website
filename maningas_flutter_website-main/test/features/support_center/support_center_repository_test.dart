import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:patient_portal_flutter/core/network/api_client.dart';
import 'package:patient_portal_flutter/features/support_center/support_center_repository.dart';

void main() {
  test(
    'uses the support center routes and parses patient conversations',
    () async {
      final requests = <http.Request>[];
      final repository = ApiSupportCenterRepository(
        ApiClient(
          client: MockClient((request) async {
            requests.add(request);
            expect(request.headers['Authorization'], 'Bearer test-token');
            return switch ('${request.method} ${request.url.path}') {
              'GET /api/patients/support/my-tickets' => http.Response(
                jsonEncode({
                  'tickets': [
                    {
                      'ticket_id': 42,
                      'subject': 'Appointment question',
                      'category': 'Appointment',
                      'status': 'In Progress',
                      'priority': 'Medium',
                      'updated_at': '2026-10-28T01:00:00Z',
                    },
                    {
                      'id': 43,
                      'status': 'Closed',
                      'resolution': 'Cancelled by patient',
                    },
                  ],
                }),
                200,
              ),
              'GET /api/patients/support/tickets/42/messages' => http.Response(
                jsonEncode({
                  'messages': [
                    {
                      'message': 'I need help with my appointment.',
                      'sender_type': 'patient',
                      'sender_patient_id': 'patient-7',
                      'created_at': '2026-10-28T01:00:00Z',
                    },
                    {
                      'content': 'How can we help?',
                      'sender_type': 'admin',
                      'sender_name': 'Clinic Support',
                      'created_at': '2026-10-28T01:02:00Z',
                    },
                  ],
                }),
                200,
              ),
              'POST /api/patients/support/tickets' => http.Response(
                jsonEncode({
                  'success': true,
                  'ticket': {
                    'ticket_id': 44,
                    'subject': 'New concern',
                    'category': 'General Inquiry',
                    'status': 'Open',
                  },
                }),
                201,
              ),
              'PUT /api/patients/support/tickets/42/cancel' => http.Response(
                '',
                204,
              ),
              'POST /api/patients/support/tickets/42/messages' => http.Response(
                jsonEncode({'success': true}),
                201,
              ),
              'PUT /api/patients/support/tickets/42/messages/read' =>
                http.Response('', 204),
              _ => http.Response('{}', 404),
            };
          }),
          baseUri: Uri.parse('https://api.example.test'),
        ),
      );

      final tickets = await repository.getMyTickets(
        patientId: 'patient-7',
        token: 'test-token',
      );
      expect(tickets, hasLength(1));
      expect(tickets.single.id, '42');
      expect(tickets.single.status, 'In Progress');

      final messages = await repository.getMessages(
        patientId: 'patient-7',
        token: 'test-token',
        ticketId: '42',
      );
      expect(messages, hasLength(2));
      expect(messages.first.isMine, isTrue);
      expect(messages.first.senderName, 'You');
      expect(messages.last.isMine, isFalse);

      final created = await repository.createTicket(
        patientId: 'patient-7',
        token: 'test-token',
        category: 'General Inquiry',
        subject: 'New concern',
        description: 'Please help.',
        priority: 'Medium',
      );
      expect(created?.id, '44');
      expect(jsonDecode(requests[2].body), {
        'category': 'General Inquiry',
        'subject': 'New concern',
        'description': 'Please help.',
        'priority': 'Medium',
      });

      await repository.cancelTicket(token: 'test-token', ticketId: '42');
      await repository.sendMessage(
        token: 'test-token',
        ticketId: '42',
        message: 'A reply',
      );
      expect(jsonDecode(requests[4].body), {'message': 'A reply'});
      await repository.markMessagesRead(token: 'test-token', ticketId: '42');

      expect(
        requests.map((request) => '${request.method} ${request.url.path}'),
        [
          'GET /api/patients/support/my-tickets',
          'GET /api/patients/support/tickets/42/messages',
          'POST /api/patients/support/tickets',
          'PUT /api/patients/support/tickets/42/cancel',
          'POST /api/patients/support/tickets/42/messages',
          'PUT /api/patients/support/tickets/42/messages/read',
        ],
      );
    },
  );

  test('encodes ticket identifiers in support message routes', () async {
    final repository = ApiSupportCenterRepository(
      ApiClient(
        client: MockClient((request) async {
          expect(
            request.url.path,
            '/api/patients/support/tickets/case%2F9/messages',
          );
          return http.Response(jsonEncode({'messages': []}), 200);
        }),
        baseUri: Uri.parse('https://api.example.test'),
      ),
    );

    final messages = await repository.getMessages(
      patientId: 'patient-7',
      token: 'test-token',
      ticketId: 'case/9',
    );
    expect(messages, isEmpty);
  });
}
