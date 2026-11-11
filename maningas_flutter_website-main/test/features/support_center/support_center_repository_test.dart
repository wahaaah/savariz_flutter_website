import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:patient_portal_flutter/core/network/api_client.dart';
import 'package:patient_portal_flutter/features/support_center/support_center_repository.dart';
import 'package:patient_portal_flutter/features/support_center/support_image_attachment.dart';

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
                      'attachment_url': 'https://cdn.example.test/support.png',
                      'attachment_name': 'support.png',
                      'attachment_mime_type': 'image/png',
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
      expect(
        messages.last.attachmentUrl,
        'https://cdn.example.test/support.png',
      );
      expect(messages.last.attachmentName, 'support.png');
      expect(messages.last.attachmentMimeType, 'image/png');

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

  test('sends an image and optional message as multipart form data', () async {
    final repository = ApiSupportCenterRepository(
      ApiClient(
        client: MockClient((request) async {
          expect(
            request.headers.keys.map((key) => key.toLowerCase()),
            contains('authorization'),
          );
          expect(
            request.headers['content-type'],
            startsWith('multipart/form-data; boundary='),
          );
          expect(request.body, contains('name="message"'));
          expect(request.body, contains('Look at this screenshot'));
          expect(
            request.body,
            contains('name="image"; filename="screenshot.png"'),
          );
          expect(request.body, contains('content-type: image/png'));
          expect(request.body, contains('abc'));
          return http.Response(jsonEncode({'success': true}), 201);
        }),
        baseUri: Uri.parse('https://api.example.test'),
      ),
    );

    await repository.sendMessage(
      token: 'test-token',
      ticketId: '42',
      message: 'Look at this screenshot',
      attachment: SupportImageAttachment(
        bytes: Uint8List.fromList([97, 98, 99]),
        fileName: 'screenshot.png',
        mimeType: 'image/png',
      ),
    );
  });
}
