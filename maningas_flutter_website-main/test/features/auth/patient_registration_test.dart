import 'package:flutter_test/flutter_test.dart';
import 'package:patient_portal_flutter/features/auth/domain/patient_registration_validation.dart';

void main() {
  test('patient names accept letters and supported name punctuation only', () {
    expect(isValidPatientName("Anne-Marie O'Neil"), isTrue);
    expect(isValidPatientName('St. John'), isTrue);
    expect(isValidPatientName('Élodie Núñez'), isTrue);
    expect(isValidPatientName('Juan123'), isFalse);
    expect(isValidPatientName('Juan@DelaCruz'), isFalse);
  });

  test('name input filtering rejects digits and unsupported characters', () {
    expect(isValidPatientNameInput('Juan Dela-Cruz'), isTrue);
    expect(isValidPatientNameInput('Juan3'), isFalse);
    expect(isValidPatientNameInput('Juan@'), isFalse);
  });

  test('registration only accepts Gmail addresses', () {
    expect(isAcceptedPatientEmail('patient@gmail.com'), isTrue);
    expect(isAcceptedPatientEmail('Patient@GMAIL.COM'), isTrue);
    expect(isAcceptedPatientEmail('patient@tempmail.com'), isFalse);
    expect(isAcceptedPatientEmail('patient@example.com'), isFalse);
    expect(isAcceptedPatientEmail('patient@gmail.com.example.com'), isFalse);
  });

  test('ZIP codes must contain exactly four digits', () {
    expect(isValidPatientZipCode('3019'), isTrue);
    expect(isValidPatientZipCode('0000'), isTrue);
    expect(isValidPatientZipCode('319'), isFalse);
    expect(isValidPatientZipCode('30190'), isFalse);
    expect(isValidPatientZipCode('30A9'), isFalse);
  });
}
