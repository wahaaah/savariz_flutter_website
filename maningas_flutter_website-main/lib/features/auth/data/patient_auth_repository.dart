import '../domain/patient_session.dart';
import '../domain/patient_registration.dart';

abstract interface class PatientAuthRepository {
  Future<PatientAuthResult> login({
    required String email,
    required String password,
    required bool rememberMe,
  });

  Future<PatientSession> validateSession(String token);

  Future<PatientRegistrationResult> register(
    PatientRegistrationRequest request,
  );

  Future<EmailVerificationResult> verifyEmail({
    required String email,
    required String otp,
  });

  Future<ResendVerificationResult> resendVerification({required String email});

  Future<String> requestPasswordReset({required String email});

  Future<String> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  });
}
