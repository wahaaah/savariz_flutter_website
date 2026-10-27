class TryOnConfig {
  const TryOnConfig._();

  static Uri? buildLaunchUri({
    required int frameId,
    required Uri apiBaseUri,
    required String websiteOrigin,
  }) {
    if (frameId <= 0 || !_isClinicApiOrigin(apiBaseUri)) {
      return null;
    }

    final websiteUri = Uri.tryParse(websiteOrigin);
    if (websiteUri == null || !_isSecureWebsiteOrigin(websiteUri)) {
      return null;
    }

    return websiteUri.replace(
      path: '/try_on.html',
      queryParameters: {'mobileTryOn': 'true', 'frameId': '$frameId'},
    );
  }

  static bool _isClinicApiOrigin(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == 'api.gonzalesvisionclinic.com' &&
      uri.port == 443 &&
      (uri.path.isEmpty || uri.path == '/') &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      uri.userInfo.isEmpty;

  static bool _isSecureWebsiteOrigin(Uri uri) {
    if (uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return false;
    }
    if (uri.scheme == 'https') return true;
    return uri.scheme == 'http' &&
        const {'localhost', '127.0.0.1', '::1'}.contains(uri.host);
  }
}
