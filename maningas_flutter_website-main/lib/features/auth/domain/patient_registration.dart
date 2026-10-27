class PatientRegistrationRequest {
  const PatientRegistrationRequest({
    required this.name,
    required this.age,
    required this.dateOfBirth,
    required this.gender,
    required this.contact,
    required this.email,
    required this.password,
    required this.addressUnit,
    required this.addressStreet,
    required this.addressBarangay,
    required this.addressCityMunicipality,
    required this.addressProvince,
    required this.addressZipCode,
  });

  final String name;
  final int age;
  final String dateOfBirth;
  final String gender;
  final String contact;
  final String email;
  final String password;
  final String addressUnit;
  final String addressStreet;
  final String addressBarangay;
  final String addressCityMunicipality;
  final String addressProvince;
  final String addressZipCode;

  Map<String, Object?> toJson() => {
    'name': name,
    'age': age,
    'date_of_birth': dateOfBirth,
    'gender': gender,
    'address_unit': addressUnit,
    'address_street': addressStreet,
    'address_barangay': addressBarangay,
    'address_city_municipality': addressCityMunicipality,
    'address_province': addressProvince,
    'address_zip_code': addressZipCode,
    'contact': contact,
    'email': email,
    'password': password,
  };
}

class PatientRegistrationResult {
  const PatientRegistrationResult({
    required this.email,
    required this.name,
    required this.requiresEmailVerification,
  });

  final String email;
  final String name;
  final bool requiresEmailVerification;
}

class EmailVerificationResult {
  const EmailVerificationResult({required this.message});

  final String message;
}

class ResendVerificationResult {
  const ResendVerificationResult({
    required this.message,
    required this.emailVerified,
  });

  final String message;
  final bool emailVerified;
}
