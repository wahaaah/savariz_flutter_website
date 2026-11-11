enum ApiFailureKind { network, timeout, http, invalidResponse, securityBlocked }

class ApiFailure implements Exception {
  const ApiFailure({
    required this.kind,
    required this.message,
    this.statusCode,
    this.code,
    this.retryAfterSeconds,
  });

  final ApiFailureKind kind;
  final String message;
  final int? statusCode;
  final String? code;
  final int? retryAfterSeconds;

  @override
  String toString() => message;
}
