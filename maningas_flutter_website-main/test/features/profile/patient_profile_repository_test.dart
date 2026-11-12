import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:patient_portal_flutter/core/network/api_client.dart';
import 'package:patient_portal_flutter/features/profile/patient_profile_repository.dart';

void main() {
  test('sends profile edits to the authenticated patient profile endpoint', () async {
    final update = PatientProfileUpdate(
      firstName: 'Juan',
      middleName: 'Santos',
      lastName: 'Dela Cruz',
      dateOfBirth: '1995-04-12',
      gender: 'Male',
      contactNumber: '09171234567',
      addressUnit: 'Block 5 Lot 10',
      street: 'Sampaguita Street',
      barangay: 'San Isidro',
      cityMunicipality: 'Example City',
      province: 'Example Province',
      zipCode: '3019',
    );
    final repository = ApiPatientProfileRepository(
      ApiClient(
        client: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(request.url.path, '/api/patients/me/profile');
          expect(jsonDecode(request.body), update.toJson());
          return http.Response(
            jsonEncode({
              'success': true,
              'patient_id': 'GVC-1234',
              'name': update.fullName,
            }),
            200,
          );
        }),
        baseUri: Uri.parse('https://api.example.test'),
      ),
    );

    await repository.updatePatientDetails(
      patientId: 'GVC-1234',
      token: 'patient-token',
      update: update,
    );
  });

  test('preserves a legacy full-address value in profile updates', () {
    const update = PatientProfileUpdate(
      firstName: 'Juan',
      middleName: '',
      lastName: 'Dela Cruz',
      dateOfBirth: '1995-04-12',
      gender: 'Male',
      contactNumber: '09171234567',
      addressUnit: '',
      street: '',
      barangay: '',
      cityMunicipality: '',
      province: '',
      zipCode: '',
      legacyAddress: 'BLK 208 LT 27 ST ANNE DECA HOMES MARILAO BULACAN',
    );

    expect(update.toJson()['address'], update.legacyAddress);
    expect(update.toJson().containsKey('address_unit'), isFalse);
  });

  test('uses a formatted API address when components are not returned', () {
    final details = PatientProfileDetails.fromResponse({
      'patient': {
        'patient_id': 12,
        'address': 'Block 5 Lot 10, Sampaguita St, San Isidro, Example City',
      },
    });

    expect(
      details.address,
      'Block 5 Lot 10, Sampaguita St, San Isidro, Example City',
    );
    expect(details.addressUnit, isNull);
    expect(details.street, isNull);
    expect(details.cityMunicipality, isNull);
  });

  test('reads structured address fields from a camel-case address object', () {
    final details = PatientProfileDetails.fromResponse({
      'data': {
        'patient': {
          'patientId': 12,
          'address': {
            'unit': 'Block 5 Lot 10',
            'street': 'Sampaguita Street',
            'barangay': 'San Isidro',
            'city': 'Example City',
            'province': 'Example Province',
            'zipCode': '1234',
          },
        },
      },
    });

    expect(details.addressUnit, 'Block 5 Lot 10');
    expect(details.street, 'Sampaguita Street');
    expect(details.barangay, 'San Isidro');
    expect(details.cityMunicipality, 'Example City');
    expect(details.province, 'Example Province');
    expect(details.zipCode, '1234');
    expect(
      details.address,
      'Block 5 Lot 10, Sampaguita Street, San Isidro, Example City, '
      'Example Province 1234',
    );
  });

  test('prefers canonical top-level address fields over nested aliases', () {
    final details = PatientProfileDetails.fromResponse({
      'address_unit': 'Unit 4',
      'address': {'unit': 'Unit 9', 'province': 'Example Province'},
    });

    expect(details.addressUnit, 'Unit 4');
    expect(details.province, 'Example Province');
  });

  test('reads saved address columns from a patient database response', () {
    final details = PatientProfileDetails.fromResponse({
      'patient_id': 'GVC-1234',
      'name': 'Juan Dela Cruz',
      'address': 'Unit 4, Mabini Street, San Isidro, Example City',
      'address_unit': 'Unit 4',
      'address_street': 'Mabini Street',
      'address_barangay': 'San Isidro',
      'address_city_municipality': 'Example City',
      'address_province': 'Example Province',
      'address_zip_code': '3019',
    });

    expect(details.addressUnit, 'Unit 4');
    expect(details.street, 'Mabini Street');
    expect(details.barangay, 'San Isidro');
    expect(details.cityMunicipality, 'Example City');
    expect(details.province, 'Example Province');
    expect(details.zipCode, '3019');
  });
}
