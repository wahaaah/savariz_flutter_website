bool isValidPatientName(String value) =>
    RegExp(
      r"^[\p{L}\p{M}]+(?:[ .'-]*[\p{L}\p{M}]+)*[.'-]?$",
      unicode: true,
    ).hasMatch(value.trim());

bool isValidPatientNameInput(String value) =>
    RegExp(r"^[\p{L}\p{M} .'-]*$", unicode: true).hasMatch(value);

bool isAcceptedPatientEmail(String value) =>
    RegExp(r'^[^\s@]+@gmail\.com$', caseSensitive: false).hasMatch(value.trim());

bool isValidPatientZipCode(String value) =>
    RegExp(r'^\d{4}$').hasMatch(value.trim());

bool isValidPhilippineMobileNumber(String value) {
  return RegExp(r'^9\d{9}$').hasMatch(value.trim());
}
