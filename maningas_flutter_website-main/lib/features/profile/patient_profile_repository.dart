import '../../core/network/api_client.dart';
import '../../core/network/api_failure.dart';

class PatientProfileDetails {
  const PatientProfileDetails({
    this.patientId,
    this.fullName,
    this.firstName,
    this.middleName,
    this.lastName,
    this.email,
    this.dateOfBirth,
    this.gender,
    this.contactNumber,
    this.address,
    this.addressUnit,
    this.street,
    this.barangay,
    this.cityMunicipality,
    this.province,
    this.zipCode,
  });

  factory PatientProfileDetails.fromResponse(Map<String, dynamic> response) {
    final rawPatient = _unwrapPatient(response);

    final address =
        rawPatient['address'] ??
        rawPatient['patient_address'] ??
        rawPatient['address_details'] ??
        rawPatient['residential_address'];
    final addressMap = address is Map<String, dynamic>
        ? address
        : const <String, dynamic>{};
    final firstName = _firstValue([
      rawPatient['first_name'],
      rawPatient['firstname'],
      rawPatient['firstName'],
    ]);
    final middleName = _firstValue([
      rawPatient['middle_name'],
      rawPatient['middlename'],
      rawPatient['middleName'],
    ]);
    final lastName = _firstValue([
      rawPatient['last_name'],
      rawPatient['lastname'],
      rawPatient['lastName'],
    ]);
    final fullName = _firstValue([
      rawPatient['full_name'],
      rawPatient['fullName'],
      rawPatient['name'],
    ]) ??
        [firstName, middleName, lastName]
            .whereType<String>()
            .where((part) => part.trim().isNotEmpty)
            .join(' ');
    final addressString = address is String ? _nonEmpty(address) : null;
    final addressUnit = _firstValue([
      rawPatient['address_unit'],
      rawPatient['addressUnit'],
      rawPatient['unit'],
      rawPatient['house_unit'],
      rawPatient['house_number'],
      addressMap['address_unit'],
      addressMap['addressUnit'],
      addressMap['unit'],
      addressMap['house_unit'],
      addressMap['house_number'],
    ]);
    final street = _firstValue([
      rawPatient['address_street'],
      rawPatient['addressStreet'],
      rawPatient['street'],
      addressMap['address_street'],
      addressMap['addressStreet'],
      addressMap['street'],
    ]);
    final barangay = _firstValue([
      rawPatient['address_barangay'],
      rawPatient['addressBarangay'],
      rawPatient['barangay'],
      addressMap['address_barangay'],
      addressMap['addressBarangay'],
      addressMap['barangay'],
    ]);
    final cityMunicipality = _firstValue([
      rawPatient['address_city_municipality'],
      rawPatient['addressCityMunicipality'],
      rawPatient['city_municipality'],
      rawPatient['cityMunicipality'],
      rawPatient['municipality'],
      rawPatient['city'],
      addressMap['address_city_municipality'],
      addressMap['addressCityMunicipality'],
      addressMap['city_municipality'],
      addressMap['cityMunicipality'],
      addressMap['municipality'],
      addressMap['city'],
    ]);
    final province = _firstValue([
      rawPatient['address_province'],
      rawPatient['addressProvince'],
      rawPatient['province'],
      addressMap['address_province'],
      addressMap['addressProvince'],
      addressMap['province'],
    ]);
    final addressParts = [
      addressUnit,
      street,
      barangay,
      cityMunicipality,
      province,
    ].whereType<String>().toList(growable: false);
    final zipCode = _firstValue([
      rawPatient['address_zip_code'],
      rawPatient['addressZipCode'],
      rawPatient['zip_code'],
      rawPatient['zipCode'],
      rawPatient['postal_code'],
      rawPatient['postalCode'],
      addressMap['address_zip_code'],
      addressMap['addressZipCode'],
      addressMap['zip_code'],
      addressMap['zipCode'],
      addressMap['postal_code'],
      addressMap['postalCode'],
    ]);
    final formattedAddress = [
      if (addressParts.isNotEmpty) addressParts.join(', '),
      ?zipCode,
    ].join(' ');

    return PatientProfileDetails(
      patientId: _firstValue([
        rawPatient['patient_id'],
        rawPatient['patientId'],
        rawPatient['id'],
      ]),
      fullName: _nonEmpty(fullName),
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      email: _firstValue([
        rawPatient['email'],
        rawPatient['email_address'],
        rawPatient['emailAddress'],
      ]),
      dateOfBirth: _firstValue([
        rawPatient['date_of_birth'],
        rawPatient['dateOfBirth'],
        rawPatient['dob'],
        rawPatient['birth_date'],
        rawPatient['birthDate'],
        rawPatient['birthdate'],
        rawPatient['dateofbirth'],
      ]),
      gender: _firstValue([rawPatient['gender']]),
      contactNumber: _firstValue([
        rawPatient['contact_number'],
        rawPatient['contactNumber'],
        rawPatient['contact_no'],
        rawPatient['contactNo'],
        rawPatient['phone'],
        rawPatient['phone_number'],
        rawPatient['phoneNumber'],
        rawPatient['mobile'],
        rawPatient['mobile_number'],
        rawPatient['mobileNumber'],
        rawPatient['telephone'],
        rawPatient['telephone_number'],
        rawPatient['telephoneNumber'],
        rawPatient['contact'],
        _nestedContactValue(rawPatient),
      ]),
      address:
          addressString ?? (formattedAddress.isEmpty ? null : formattedAddress),
      addressUnit: addressUnit,
      street: street,
      barangay: barangay,
      cityMunicipality: cityMunicipality,
      province: province,
      zipCode: zipCode,
    );
  }

  final String? contactNumber;
  final String? address;
  final String? patientId;
  final String? fullName;
  final String? firstName;
  final String? middleName;
  final String? lastName;
  final String? email;
  final String? dateOfBirth;
  final String? gender;
  final String? addressUnit;
  final String? street;
  final String? barangay;
  final String? cityMunicipality;
  final String? province;
  final String? zipCode;
}

abstract interface class PatientProfileRepository {
  Future<PatientProfileDetails> getPatientDetails({
    required String patientId,
    required String token,
  });
}

class ApiPatientProfileRepository implements PatientProfileRepository {
  const ApiPatientProfileRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<PatientProfileDetails> getPatientDetails({
    required String patientId,
    required String token,
  }) async {
    try {
      final response = await _apiClient.getJson(
        '/api/patients/${Uri.encodeComponent(patientId)}',
        headers: {'Authorization': 'Bearer $token'},
      );
      final details = PatientProfileDetails.fromResponse(response);
      if (details.patientId != null && details.patientId != patientId) {
        throw const FormatException('Patient details ID did not match.');
      }
      return details;
    } on FormatException {
      throw const ApiFailure(
        kind: ApiFailureKind.invalidResponse,
        message: 'The clinic service returned invalid patient details.',
      );
    } on ApiFailure catch (failure) {
      if (failure.statusCode == 401 || failure.statusCode == 403) {
        throw ApiFailure(
          kind: failure.kind,
          statusCode: failure.statusCode,
          code: failure.code,
          message: failure.statusCode == 401
              ? 'Your patient session is invalid or expired. Please sign in again.'
              : 'Your account cannot access these patient details.',
        );
      }
      rethrow;
    }
  }
}

String? _firstValue(Iterable<Object?> values) {
  for (final value in values) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    if (value is num) return value.toString();
  }
  return null;
}

Map<String, dynamic> _unwrapPatient(Map<String, dynamic> response) {
  var patient = response;
  for (var depth = 0; depth < 3; depth++) {
    final nested = patient['patient'] ?? patient['data'];
    if (nested is! Map<String, dynamic>) break;
    patient = nested;
  }
  return patient;
}

Object? _nestedContactValue(Map<String, dynamic> patient) {
  const contactKeys = [
    'contact_information',
    'contactInformation',
    'contact_info',
    'contactInfo',
    'contact_details',
    'contactDetails',
  ];
  const valueKeys = [
    'contact_number',
    'contactNumber',
    'contact_no',
    'contactNo',
    'phone',
    'phone_number',
    'phoneNumber',
    'mobile',
    'mobile_number',
    'mobileNumber',
    'telephone',
    'telephone_number',
    'telephoneNumber',
    'contact',
  ];
  for (final contactKey in contactKeys) {
    final contact = patient[contactKey];
    if (contact is! Map<String, dynamic>) continue;
    for (final valueKey in valueKeys) {
      final value = contact[valueKey];
      if (value is String && value.trim().isNotEmpty) return value;
      if (value is num) return value;
    }
  }
  return null;
}

String? _nonEmpty(String value) => value.trim().isEmpty ? null : value.trim();
