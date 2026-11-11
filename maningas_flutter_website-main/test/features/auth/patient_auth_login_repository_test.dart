import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:patient_portal_flutter/core/network/api_client.dart';
import 'package:patient_portal_flutter/core/network/api_failure.dart';
import 'package:patient_portal_flutter/features/auth/data/patient_auth_api_repository.dart';

void main() {
  test('posts login details and preserves the Remember Me choice', () async {
    final repository = PatientAuthApiRepository(
      ApiClient(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/patients/login');
          expect(jsonDecode(request.body), {
            'email': 'patient@example.com',
            'password': 'patient-password',
            'rememberMe': true,
          });
          return http.Response(
            jsonEncode({
              'success': true,
              'patient': {
                'patient_id': 42,
                'name': 'Patient Example',
                'email': 'patient@example.com',
                'email_verified': true,
              },
              'token': 'access-token',
            }),
            200,
          );
        }),
        baseUri: Uri.parse('https://api.example.test'),
      ),
    );

    final result = await repository.login(
      email: ' patient@example.com ',
      password: 'patient-password',
      rememberMe: true,
    );

    final session = result.session;
    expect(session, isNotNull);
    expect(session!.patientId, '42');
    expect(session.token, 'access-token');
    expect(session.rememberMe, isTrue);
  });

  test(
    'returns an email-verification handoff for an unverified account',
    () async {
      final repository = PatientAuthApiRepository(
        ApiClient(
          client: MockClient((_) async {
            return http.Response(
              jsonEncode({
                'success': true,
                'patient': {
                  'email': 'patient@example.com',
                  'email_verified': false,
                },
                'message': 'Verify your email address.',
              }),
              200,
            );
          }),
          baseUri: Uri.parse('https://api.example.test'),
        ),
      );

      final result = await repository.login(
        email: 'patient@example.com',
        password: 'patient-password',
        rememberMe: false,
      );

      expect(result.requiresEmailVerification, isTrue);
      expect(result.email, 'patient@example.com');
      expect(result.session, isNull);
    },
  );

  test('surfaces the login-attempt limit response from the API', () async {
    final repository = PatientAuthApiRepository(
      ApiClient(
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({'error': 'Too many attempts. Try again later.'}),
            429,
          );
        }),
        baseUri: Uri.parse('https://api.example.test'),
      ),
    );

    await expectLater(
      repository.login(
        email: 'patient@example.com',
        password: 'patient-password',
        rememberMe: false,
      ),
      throwsA(
        isA<ApiFailure>()
            .having((failure) => failure.statusCode, 'statusCode', 429)
            .having(
              (failure) => failure.message,
              'message',
              'Too many attempts. Try again later.',
            ),
      ),
    );
  });

  test('continues to accept top-level patient details', () async {
    final repository = PatientAuthApiRepository(
      ApiClient(
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'success': true,
              'patient_id': 42,
              'name': 'Patient Example',
              'email': 'patient@example.com',
              'email_verified': true,
              'token': 'access-token',
            }),
            200,
          );
        }),
        baseUri: Uri.parse('https://api.example.test'),
      ),
    );

    final result = await repository.login(
      email: 'patient@example.com',
      password: 'patient-password',
      rememberMe: false,
    );

    expect(result.session?.patientId, '42');
    expect(result.session?.email, 'patient@example.com');
  });

  test('requests a password reset OTP using the normalized email', () async {
    final repository = PatientAuthApiRepository(
      ApiClient(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/patients/forgot-password');
          expect(jsonDecode(request.body), {'email': 'patient@example.com'});
          return http.Response(
            jsonEncode({'success': true, 'message': 'OTP sent.'}),
            200,
          );
        }),
        baseUri: Uri.parse('https://api.example.test'),
      ),
    );

    final message = await repository.requestPasswordReset(
      email: ' Patient@Example.com ',
    );

    expect(message, 'OTP sent.');
  });

  test('resets the password with the provided OTP and new password', () async {
    final repository = PatientAuthApiRepository(
      ApiClient(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/patients/reset-password');
          expect(jsonDecode(request.body), {
            'email': 'patient@example.com',
            'otp': '123456',
            'newPassword': 'ValidPass123',
          });
          return http.Response(
            jsonEncode({'success': true, 'message': 'Password changed.'}),
            200,
          );
        }),
        baseUri: Uri.parse('https://api.example.test'),
      ),
    );

    final message = await repository.resetPassword(
      email: ' Patient@Example.com ',
      otp: '123456',
      newPassword: 'ValidPass123',
    );

    expect(message, 'Password changed.');
  });

  test(
    'surfaces password reset rejection from a successful HTTP response',
    () async {
    final repository = PatientAuthApiRepository(
      ApiClient(
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({'success': false, 'message': 'Invalid OTP.'}),
            200,
          );
        }),
        baseUri: Uri.parse('https://api.example.test'),
      ),
    );

      await expectLater(
        repository.resetPassword(
        email: 'patient@example.com',
        otp: '123456',
        newPassword: 'ValidPass123',
        ),
        throwsA(
          isA<ApiFailure>().having(
            (failure) => failure.message,
            'message',
            'Invalid OTP.',
          ),
        ),
      );
    },
  );
}
