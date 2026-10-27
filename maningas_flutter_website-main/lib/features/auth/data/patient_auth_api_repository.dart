import '../../../core/network/api_client.dart';
import '../../../core/network/api_failure.dart';
import '../domain/patient_registration.dart';
import '../domain/patient_session.dart';
import 'patient_auth_repository.dart';

class PatientAuthApiRepository implements PatientAuthRepository {
  const PatientAuthApiRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<PatientAuthResult> login({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    final response = await _apiClient.postJson(
      '/api/patients/login',
      body: {
        'email': email.trim(),
        'password': password,
        'rememberMe': rememberMe,
      },
    );

    final patient = response['patient'];
    final patientData = patient is Map<String, dynamic> ? patient : response;
    final emailVerified =
        patientData['email_verified'] ?? response['email_verified'];
    final responseEmail = patientData['email'];

    if (response['success'] == true && emailVerified == false) {
      if (responseEmail is! String || responseEmail.trim().isEmpty) {
        throw const ApiFailure(
          kind: ApiFailureKind.invalidResponse,
          message: 'The clinic service returned incomplete verification details.',
        );
      }
      return PatientAuthResult.verificationRequired(
        email: responseEmail.trim(),
      );
    }

    final token = response['token'];
    final patientId = patientData['patient_id'];
    final name = patientData['name'];
    if (response['success'] != true ||
        token is! String ||
        token.isEmpty ||
        patientId == null ||
        patientId.toString().isEmpty ||
        name is! String ||
        responseEmail is! String ||
        emailVerified != true) {
      throw const ApiFailure(
        kind: ApiFailureKind.invalidResponse,
        message: 'The clinic service returned incomplete sign-in details.',
      );
    }

    return PatientAuthResult.api(
      PatientSession(
        patientId: patientId.toString(),
        name: name,
        email: responseEmail,
        token: token,
        rememberMe: rememberMe,
      ),
    );
  }

  @override
  Future<PatientSession> validateSession(String token) async {
    final response = await _apiClient.getJson(
      '/api/patients/auth/me',
      headers: {'Authorization': 'Bearer $token'},
    );
    final patientId = response['patient_id'];
    final name = response['name'];
    final email = response['email'];
    final status = response['status'];
    if (response['success'] != true ||
        patientId == null ||
        patientId.toString().isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        email is! String ||
        email.trim().isEmpty ||
        status is! String ||
        status.trim().isEmpty ||
        response['email_verified'] != true) {
      throw const ApiFailure(
        kind: ApiFailureKind.invalidResponse,
        message: 'The clinic service returned incomplete session details.',
      );
    }

    return PatientSession(
      patientId: patientId.toString(),
      name: name,
      email: email,
      token: token,
      rememberMe: false,
      status: status,
      emailVerified: true,
    );
  }

  @override
  Future<PatientRegistrationResult> register(
    PatientRegistrationRequest request,
  ) async {
    final response = await _apiClient.postJson(
      '/api/patients/register',
      body: request.toJson(),
    );
    if (response['success'] == false) {
      final message = response['error'] ?? response['message'];
      throw ApiFailure(
        kind: ApiFailureKind.http,
        message: message is String && message.trim().isNotEmpty
            ? message.trim()
            : 'Registration failed. Please try again.',
      );
    }

    final responseEmail = response['email'];
    final responseName = response['name'];
    return PatientRegistrationResult(
      email: responseEmail is String && responseEmail.trim().isNotEmpty
          ? responseEmail.trim()
          : request.email,
      name: responseName is String && responseName.trim().isNotEmpty
          ? responseName.trim()
          : request.name,
      requiresEmailVerification: true,
    );
  }

  @override
  Future<EmailVerificationResult> verifyEmail({
    required String email,
    required String otp,
  }) async {
    final response = await _apiClient.postJson(
      '/api/patients/verify-email',
      body: {'email': email.trim(), 'otp': otp},
    );
    final patientId = response['patient_id'];
    final verifiedEmail = response['email'];
    if (response['success'] != true ||
        response['email_verified'] != true ||
        patientId == null ||
        patientId.toString().isEmpty ||
        verifiedEmail is! String ||
        verifiedEmail.trim().toLowerCase() != email.trim().toLowerCase()) {
      throw const ApiFailure(
        kind: ApiFailureKind.invalidResponse,
        message: 'The clinic service returned an invalid verification result.',
      );
    }
    final message = response['message'];
    return EmailVerificationResult(
      message: message is String && message.trim().isNotEmpty
          ? message.trim()
          : 'Email verified. Please sign in.',
    );
  }

  @override
  Future<ResendVerificationResult> resendVerification({
    required String email,
  }) async {
    final response = await _apiClient.postJson(
      '/api/patients/resend-verification',
      body: {'email': email.trim()},
    );
    if (response['success'] != true || response['email_verified'] is! bool) {
      throw const ApiFailure(
        kind: ApiFailureKind.invalidResponse,
        message: 'The clinic service returned an invalid resend result.',
      );
    }
    final message = response['message'];
    return ResendVerificationResult(
      message: message is String && message.trim().isNotEmpty
          ? message.trim()
          : 'The verification request was accepted.',
      emailVerified: response['email_verified'] == true,
    );
  }

  @override
  Future<String> requestPasswordReset({required String email}) async {
    final response = await _apiClient.postJson(
      '/api/patients/forgot-password',
      body: {'email': email.trim().toLowerCase()},
    );
    _ensureSuccessfulResponse(response, 'Unable to process your request.');
    return _responseMessage(
      response,
      'A verification code has been sent to your email. The code expires in 5 minutes.',
    );
  }

  @override
  Future<String> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    final response = await _apiClient.postJson(
      '/api/patients/reset-password',
      body: {
        'email': email.trim().toLowerCase(),
        'otp': otp.trim(),
        'newPassword': newPassword,
      },
    );
    _ensureSuccessfulResponse(response, 'Unable to reset your password.');
    return _responseMessage(
      response,
      'Your password has been changed successfully.',
    );
  }

  void _ensureSuccessfulResponse(
    Map<String, dynamic> response,
    String fallback,
  ) {
    if (response['success'] == false) {
      final message = response['message'] ?? response['error'];
      throw ApiFailure(
        kind: ApiFailureKind.http,
        message: message is String && message.trim().isNotEmpty
            ? message.trim()
            : fallback,
      );
    }
  }

  String _responseMessage(Map<String, dynamic> response, String fallback) {
    final message = response['message'];
    return message is String && message.trim().isNotEmpty
        ? message.trim()
        : fallback;
  }
}
