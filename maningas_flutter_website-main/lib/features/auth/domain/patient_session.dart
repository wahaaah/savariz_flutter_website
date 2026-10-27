class PatientSession {
  const PatientSession({
    required this.patientId,
    required this.name,
    required this.email,
    required this.token,
    required this.rememberMe,
    this.status,
    this.emailVerified,
  });

  final String patientId;
  final String name;
  final String email;
  final String token;
  final bool rememberMe;
  final String? status;
  final bool? emailVerified;
}

class PatientAuthResult {
  const PatientAuthResult.api(this.session)
    : email = null,
      requiresEmailVerification = false;

  const PatientAuthResult.verificationRequired({required this.email})
    : session = null,
      requiresEmailVerification = true;

  final PatientSession? session;
  final String? email;
  final bool requiresEmailVerification;
}
