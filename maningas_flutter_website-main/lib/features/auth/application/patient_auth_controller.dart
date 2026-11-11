import 'package:flutter/foundation.dart';

import '../../../core/network/api_failure.dart';
import '../data/patient_auth_repository.dart';
import '../domain/patient_registration.dart';
import '../domain/patient_session.dart';
import '../domain/patient_session_store.dart';

class PatientAuthController extends ChangeNotifier {
  PatientAuthController({
    required this.repository,
    required this.sessionStore,
    this.onDispose,
  });

  final PatientAuthRepository repository;
  final PatientSessionStore sessionStore;
  final VoidCallback? onDispose;
  Future<PatientAuthResult>? _pendingLogin;
  final Map<String, DateTime> _loginLockouts = {};
  bool _isLoading = false;
  Future<PatientRegistrationResult>? _pendingRegistration;
  Future<EmailVerificationResult>? _pendingVerification;
  Future<ResendVerificationResult>? _pendingResend;
  bool _isRegistering = false;
  bool _isVerifyingEmail = false;
  bool _isResendingVerification = false;
  bool _isLoadingIdentity = false;
  ApiFailure? _identityFailure;
  Future<bool>? _pendingIdentityLoad;
  int _authGeneration = 0;

  bool get isLoading => _isLoading;
  bool get isRegistering => _isRegistering;
  bool get isVerifyingEmail => _isVerifyingEmail;
  bool get isResendingVerification => _isResendingVerification;
  bool get isLoadingIdentity => _isLoadingIdentity;
  ApiFailure? get identityFailure => _identityFailure;
  PatientSession? get currentSession => sessionStore.currentSession;

  Future<bool> loadCurrentPatientIdentity() {
    final session = currentSession;
    if (session == null) return Future.value(false);
    if (session.status != null) return Future.value(true);
    final pending = _pendingIdentityLoad;
    if (pending != null) return pending;

    final generation = _authGeneration;
    _isLoadingIdentity = true;
    _identityFailure = null;
    notifyListeners();
    final operation = _loadPatientIdentity(session, generation);
    _pendingIdentityLoad = operation;
    return operation.whenComplete(() {
      if (generation != _authGeneration) return;
      _pendingIdentityLoad = null;
      _isLoadingIdentity = false;
      notifyListeners();
    });
  }

  Future<bool> _loadPatientIdentity(
    PatientSession requestedSession,
    int generation,
  ) async {
    try {
      final identity = await repository.validateSession(requestedSession.token);
      final current = currentSession;
      if (generation != _authGeneration ||
          current == null ||
          current.token != requestedSession.token ||
          current.patientId != requestedSession.patientId) {
        return false;
      }
      if (identity.patientId != requestedSession.patientId) {
        _identityFailure = const ApiFailure(
          kind: ApiFailureKind.invalidResponse,
          message: 'The clinic service returned a different patient identity.',
        );
        notifyListeners();
        return false;
      }
      sessionStore.save(
        PatientSession(
          patientId: identity.patientId,
          name: identity.name,
          email: identity.email,
          token: requestedSession.token,
          rememberMe: current.rememberMe,
          status: identity.status,
          emailVerified: identity.emailVerified,
        ),
      );
      notifyListeners();
      return true;
    } on ApiFailure catch (failure) {
      final current = currentSession;
      if (generation != _authGeneration ||
          current == null ||
          current.token != requestedSession.token ||
          current.patientId != requestedSession.patientId) {
        return false;
      }
      if (failure.statusCode == 401 || failure.statusCode == 403) {
        sessionStore.clear();
        _identityFailure = null;
      } else {
        _identityFailure = failure;
      }
      notifyListeners();
      return false;
    }
  }

  Future<PatientRegistrationResult> register(
    PatientRegistrationRequest request,
  ) {
    final pending = _pendingRegistration;
    if (pending != null) return pending;
    _isRegistering = true;
    notifyListeners();
    final operation = Future<PatientRegistrationResult>.sync(
      () => repository.register(request),
    );
    _pendingRegistration = operation;
    return operation.whenComplete(() {
      _pendingRegistration = null;
      _isRegistering = false;
      notifyListeners();
    });
  }

  Future<EmailVerificationResult> verifyEmail({
    required String email,
    required String otp,
  }) {
    final pending = _pendingVerification;
    if (pending != null) return pending;
    _isVerifyingEmail = true;
    notifyListeners();
    final operation = Future<EmailVerificationResult>.sync(
      () => repository.verifyEmail(email: email, otp: otp),
    );
    _pendingVerification = operation;
    return operation.whenComplete(() {
      _pendingVerification = null;
      _isVerifyingEmail = false;
      notifyListeners();
    });
  }

  Future<ResendVerificationResult> resendVerification({required String email}) {
    final pending = _pendingResend;
    if (pending != null) return pending;
    _isResendingVerification = true;
    notifyListeners();
    final operation = Future<ResendVerificationResult>.sync(
      () => repository.resendVerification(email: email),
    );
    _pendingResend = operation;
    return operation.whenComplete(() {
      _pendingResend = null;
      _isResendingVerification = false;
      notifyListeners();
    });
  }

  Future<bool> validateCurrentSession() async {
    final session = currentSession;
    if (session == null) return false;
    try {
      await repository.validateSession(session.token);
      return true;
    } on ApiFailure catch (failure) {
      if (failure.statusCode == 401 || failure.statusCode == 403) {
        sessionStore.clear();
        notifyListeners();
        return false;
      }
      rethrow;
    }
  }

  void logout() {
    _authGeneration++;
    _pendingIdentityLoad = null;
    _isLoadingIdentity = false;
    _identityFailure = null;
    sessionStore.clear();
    notifyListeners();
  }

  Future<PatientAuthResult> login({
    required String email,
    required String password,
    required bool rememberMe,
  }) {
    final normalizedEmail = email.trim().toLowerCase();
    final lockoutUntil = _loginLockouts[normalizedEmail];
    if (lockoutUntil != null) {
      if (DateTime.now().isBefore(lockoutUntil)) {
        final retryAfterSeconds = lockoutUntil
            .difference(DateTime.now())
            .inSeconds
            .clamp(1, 900);
        return Future.error(
          ApiFailure(
            kind: ApiFailureKind.http,
            statusCode: 429,
            code: 'LOGIN_TOO_MANY_ATTEMPTS',
            retryAfterSeconds: retryAfterSeconds,
            message:
                'Too many login attempts. Please try again in $retryAfterSeconds seconds.',
          ),
        );
      }
      _loginLockouts.remove(normalizedEmail);
    }

    final pending = _pendingLogin;
    if (pending != null) return pending;
    _isLoading = true;
    notifyListeners();
    final operation = _performLogin(
      email: email,
      password: password,
      rememberMe: rememberMe,
    );
    _pendingLogin = operation;
    return operation.whenComplete(() {
      _pendingLogin = null;
      _isLoading = false;
      notifyListeners();
    });
  }

  Future<PatientAuthResult> _performLogin({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    late final PatientAuthResult result;
    try {
      result = await repository.login(
        email: email,
        password: password,
        rememberMe: rememberMe,
      );
    } on ApiFailure catch (failure) {
      if (failure.code == 'LOGIN_TOO_MANY_ATTEMPTS') {
        final retryAfterSeconds = (failure.retryAfterSeconds ?? 900)
            .clamp(1, 900)
            .toInt();
        _loginLockouts[email.trim().toLowerCase()] = DateTime.now().add(
          Duration(seconds: retryAfterSeconds),
        );
      }
      rethrow;
    }
    final session = result.session;
    if (session == null) return result;
    _loginLockouts.remove(email.trim().toLowerCase());
    _authGeneration++;
    _pendingIdentityLoad = null;
    _isLoadingIdentity = false;
    _identityFailure = null;
    sessionStore.save(session);
    return result;
  }

  @override
  void dispose() {
    _authGeneration++;
    _pendingIdentityLoad = null;
    _isLoadingIdentity = false;
    onDispose?.call();
    super.dispose();
  }
}
