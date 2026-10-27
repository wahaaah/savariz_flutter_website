import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:patient_portal_flutter/core/network/api_client.dart';
import 'package:patient_portal_flutter/features/auth/data/patient_auth_api_repository.dart';
import 'package:patient_portal_flutter/features/auth/domain/patient_registration.dart';

void main() {
  test(
    'posts registration to the clinic API and requires email verification',
    () async {
      final request = PatientRegistrationRequest(
        name: 'Juan Dela Cruz',
        age: 25,
        dateOfBirth: '2001-01-15',
        gender: 'Male',
        contact: '09171234567',
        email: 'juan@example.com',
        password: 'a-secure-password',
        addressUnit: 'Block 5 Lot 10',
        addressStreet: 'Sampaguita Street',
        addressBarangay: 'Barangay Example',
        addressCityMunicipality: '031401',
        addressProvince: '0314',
        addressZipCode: '3020',
      );
      final repository = PatientAuthApiRepository(
        ApiClient(
          client: MockClient((httpRequest) async {
            expect(httpRequest.method, 'POST');
            expect(httpRequest.url.path, '/api/patients/register');
            expect(jsonDecode(httpRequest.body), request.toJson());
            return http.Response(
              jsonEncode({
                'success': true,
                'email': request.email,
                'name': request.name,
                'message': 'Verification email sent.',
              }),
              201,
            );
          }),
          baseUri: Uri.parse('https://api.example.test'),
        ),
      );

      final result = await repository.register(request);

      expect(result.email, request.email);
      expect(result.name, request.name);
      expect(result.requiresEmailVerification, isTrue);
    },
  );
}
