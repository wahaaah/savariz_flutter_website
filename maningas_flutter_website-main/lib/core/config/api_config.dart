class ApiConfig {
  const ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'PATIENT_API_BASE_URL',
    defaultValue: 'https://api.gonzalesvisionclinic.com',
  );

  static Uri get baseUri {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.userInfo.isNotEmpty ||
        (uri.scheme == 'http' &&
            !const {'localhost', '127.0.0.1', '::1'}.contains(uri.host))) {
      throw StateError(
        'PATIENT_API_BASE_URL must use HTTPS, or HTTP on localhost.',
      );
    }
    return uri;
  }
}
