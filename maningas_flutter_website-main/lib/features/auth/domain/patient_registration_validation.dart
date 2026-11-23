const patientRegistrationNameMaxLength = 20;
const patientRegistrationContactMaxLength = 16;

const _disposablePatientEmailDomains = <String>{
  '10minutemail.com',
  '10minutemail.net',
  'tempmail.com',
  'temp-mail.org',
  'temp-mail.io',
  'tempmailo.com',
  'guerrillamail.com',
  'guerrillamail.net',
  'mailinator.com',
  'yopmail.com',
  'getnada.com',
  'throwawaymail.com',
  'dispostable.com',
  'maildrop.cc',
  'fakeinbox.com',
  'sharklasers.com',
  'grr.la',
  'mintemail.com',
  'emailondeck.com',
  'trashmail.com',
  'mohmal.com',
  'burnermail.io',
  'inboxkitten.com',
  'tempr.email',
};

bool isValidPatientName(String value) =>
    value.trim().length <= patientRegistrationNameMaxLength &&
    RegExp(
        r"^[\p{L}\p{M}]+(?:[ .'-]*[\p{L}\p{M}]+)*[.'-]?$",
        unicode: true,
      ).hasMatch(value.trim());

bool isValidPatientNameInput(String value) =>
    RegExp(r"^[\p{L}\p{M} .'-]*$", unicode: true).hasMatch(value);

bool isValidPatientContactNumber(String value) {
  final contact = value.trim();
  return contact.length <= patientRegistrationContactMaxLength &&
      RegExp(r'^[0-9+\s-]+$').hasMatch(contact) &&
      RegExp(r'^(\+63|0)9\d{9}$')
          .hasMatch(contact.replaceAll(RegExp(r'[\s-]'), ''));
}

String formatPatientMiddleName(String value) {
  final trimmed = value.trim();
  if (RegExp(r'^\p{L}\p{M}*$', unicode: true).hasMatch(trimmed)) {
    return '$trimmed.';
  }
  return value;
}

bool isValidPatientEmail(String value) {
  final email = value.trim();
  return email.length <= 254 &&
      RegExp(
        r"^[A-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?(?:\.[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?)+$",
        caseSensitive: false,
      ).hasMatch(email);
}

bool isDisposablePatientEmail(String value) {
  final parts = value.trim().toLowerCase().split('@');
  if (parts.length != 2) return false;
  final domain = parts.last;
  return _disposablePatientEmailDomains.any(
    (blockedDomain) =>
        domain == blockedDomain || domain.endsWith('.$blockedDomain'),
  );
}

bool isValidPatientZipCode(String value) =>
    RegExp(r'^\d{4}$').hasMatch(value.trim());
