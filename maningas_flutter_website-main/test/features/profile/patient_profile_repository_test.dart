import 'package:flutter_test/flutter_test.dart';
import 'package:patient_portal_flutter/features/profile/patient_profile_repository.dart';

void main() {
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
}
