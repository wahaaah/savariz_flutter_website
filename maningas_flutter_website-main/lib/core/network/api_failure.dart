enum ApiFailureKind { network, timeout, http, invalidResponse, securityBlocked }

class ApiFailure implements Exception {
  const ApiFailure({
    required this.kind,
    required this.message,
    this.statusCode,
    this.code,
  });

  final ApiFailureKind kind;
  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => message;
}
