import 'package:flutter_test/flutter_test.dart';

import 'package:patient_portal_flutter/features/auth/domain/patient_registration.dart';

void main() {
  test('serializes the registration request using the HTML API contract', () {
    const request = PatientRegistrationRequest(
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

    expect(request.toJson(), {
      'name': 'Juan Dela Cruz',
      'age': 25,
      'date_of_birth': '2001-01-15',
      'gender': 'Male',
      'address_unit': 'Block 5 Lot 10',
      'address_street': 'Sampaguita Street',
      'address_barangay': 'Barangay Example',
      'address_city_municipality': '031401',
      'address_province': '0314',
      'address_zip_code': '3020',
      'contact': '09171234567',
      'email': 'juan@example.com',
      'password': 'a-secure-password',
    });
  });
}
