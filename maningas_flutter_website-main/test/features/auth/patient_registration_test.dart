import 'package:flutter_test/flutter_test.dart';
import 'package:patient_portal_flutter/features/auth/domain/patient_registration_validation.dart';

void main() {
  test('patient names accept letters and supported name punctuation only', () {
    expect(isValidPatientName("Anne-Marie O'Neil"), isTrue);
    expect(isValidPatientName('St. John'), isTrue);
    expect(isValidPatientName('Élodie Núñez'), isTrue);
    expect(isValidPatientName('A.'), isTrue);
    expect(isValidPatientName('Juan123'), isFalse);
    expect(isValidPatientName('Juan@DelaCruz'), isFalse);
  });

  test('registration names are limited to 20 characters', () {
    expect(isValidPatientName(List.filled(20, 'A').join()), isTrue);
    expect(isValidPatientName(List.filled(21, 'A').join()), isFalse);
  });

  test('registration contact numbers are limited and validated', () {
    expect(isValidPatientContactNumber('09171234567'), isTrue);
    expect(isValidPatientContactNumber('+63 917-123-4567'), isTrue);
    expect(isValidPatientContactNumber('0917123456789'), isFalse);
    expect(isValidPatientContactNumber('0917ABC4567'), isFalse);
  });

  test('middle initials receive a period when omitted', () {
    expect(formatPatientMiddleName('A'), 'A.');
    expect(formatPatientMiddleName(' A '), 'A.');
    expect(formatPatientMiddleName('A.'), 'A.');
    expect(formatPatientMiddleName('Ana Maria'), 'Ana Maria');
  });

  test('name input filtering rejects digits and unsupported characters', () {
    expect(isValidPatientNameInput('Juan Dela-Cruz'), isTrue);
    expect(isValidPatientNameInput('Juan3'), isFalse);
    expect(isValidPatientNameInput('Juan@'), isFalse);
  });

  test('email format accepts valid domains from different providers', () {
    expect(isValidPatientEmail('patient@gmail.com'), isTrue);
    expect(isValidPatientEmail('Patient@YAHOO.COM'), isTrue);
    expect(isValidPatientEmail('patient@outlook.com'), isTrue);
    expect(isValidPatientEmail('patient@clinic.ph'), isTrue);
    expect(isValidPatientEmail('patient@gmail.com.example.com'), isTrue);
    expect(isValidPatientEmail('patient@localhost'), isFalse);
    expect(isValidPatientEmail('patient@-example.com'), isFalse);
    expect(isValidPatientEmail('patient@'), isFalse);
    expect(isValidPatientEmail('patient @example.com'), isFalse);
    expect(
      isValidPatientEmail('${List.filled(250, 'a').join()}@example.com'),
      isFalse,
    );
  });

  test('registration blocks known disposable email domains', () {
    expect(isDisposablePatientEmail('patient@tempmail.com'), isTrue);
    expect(isDisposablePatientEmail('patient@TEMP-MAIL.ORG'), isTrue);
    expect(isDisposablePatientEmail('patient@mailinator.com'), isTrue);
    expect(isDisposablePatientEmail('patient@sub.tempmail.com'), isTrue);
    expect(isDisposablePatientEmail('patient@gmail.com'), isFalse);
    expect(isDisposablePatientEmail('patient@example.com'), isFalse);
  });

  test('ZIP codes must contain exactly four digits', () {
    expect(isValidPatientZipCode('3019'), isTrue);
    expect(isValidPatientZipCode('0000'), isTrue);
    expect(isValidPatientZipCode('319'), isFalse);
    expect(isValidPatientZipCode('30190'), isFalse);
    expect(isValidPatientZipCode('30A9'), isFalse);
  });
}
