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
  Future<bool>? _pendingSessionValidation;
  int _authGeneration = 0;

  bool get isLoading => _isLoading;
  bool get isRegistering => _isRegistering;
  bool get isVerifyingEmail => _isVerifyingEmail;
  bool get isResendingVerification => _isResendingVerification;
  bool get isLoadingIdentity => _isLoadingIdentity;
  ApiFailure? get identityFailure => _identityFailure;
  PatientSession? get currentSession => sessionStore.currentSession;

  void updateCurrentSessionName(String name) {
    final session = currentSession;
    final normalizedName = name.trim();
    if (session == null || normalizedName.isEmpty || session.name == normalizedName) {
      return;
    }
    sessionStore.save(
      PatientSession(
        patientId: session.patientId,
        name: normalizedName,
        email: session.email,
        token: session.token,
        rememberMe: session.rememberMe,
        status: session.status,
        emailVerified: session.emailVerified,
      ),
    );
    notifyListeners();
  }

  int loginLockoutRemainingSeconds(String email) {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) return 0;
    final lockoutUntil = _loginLockouts[normalizedEmail];
    if (lockoutUntil == null) return 0;

    final remaining = lockoutUntil.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _loginLockouts.remove(normalizedEmail);
      return 0;
    }
    return (remaining.inMilliseconds / 1000).ceil();
  }

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
          token: identity.token,
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
    ).then((result) {
      final session = result.session;
      if (session != null) {
        _authGeneration++;
        _pendingIdentityLoad = null;
        _pendingSessionValidation = null;
        _isLoadingIdentity = false;
        _identityFailure = null;
        sessionStore.save(session);
        notifyListeners();
      }
      return result;
    });
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
    final pending = _pendingSessionValidation;
    if (pending != null) return pending;

    final generation = _authGeneration;
    final operation = _validateCurrentSession(session, generation);
    _pendingSessionValidation = operation;
    return operation.whenComplete(() {
      if (identical(_pendingSessionValidation, operation)) {
        _pendingSessionValidation = null;
      }
    });
  }

  Future<bool> _validateCurrentSession(
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
        throw const ApiFailure(
          kind: ApiFailureKind.invalidResponse,
          message: 'The clinic service returned a different patient identity.',
        );
      }
      sessionStore.save(
        PatientSession(
          patientId: identity.patientId,
          name: identity.name,
          email: identity.email,
          token: identity.token,
          rememberMe: current.rememberMe,
          status: identity.status,
          emailVerified: identity.emailVerified,
        ),
      );
      _identityFailure = null;
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
        notifyListeners();
        return false;
      }
      _identityFailure = failure;
      notifyListeners();
      rethrow;
    }
  }

  void logout() {
    _authGeneration++;
    _pendingIdentityLoad = null;
    _pendingSessionValidation = null;
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
    final retryAfterSeconds = loginLockoutRemainingSeconds(normalizedEmail);
    if (retryAfterSeconds > 0) {
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
        notifyListeners();
      }
      rethrow;
    }
    final session = result.session;
    if (session == null) return result;
    _loginLockouts.remove(email.trim().toLowerCase());
    _authGeneration++;
    _pendingIdentityLoad = null;
    _pendingSessionValidation = null;
    _isLoadingIdentity = false;
    _identityFailure = null;
    sessionStore.save(session);
    return result;
  }

  @override
  void dispose() {
    _authGeneration++;
    _pendingIdentityLoad = null;
    _pendingSessionValidation = null;
    _isLoadingIdentity = false;
    onDispose?.call();
    super.dispose();
  }
}
