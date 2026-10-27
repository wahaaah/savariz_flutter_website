import 'package:flutter_test/flutter_test.dart';
import 'package:patient_portal_flutter/features/frames_catalog/try_on_config.dart';

void main() {
  test('builds a local same-origin Try-On URL for the selected frame', () {
    final uri = TryOnConfig.buildLaunchUri(
      frameId: 37,
      apiBaseUri: Uri.parse('https://api.gonzalesvisionclinic.com'),
      websiteOrigin: 'http://localhost:5173',
    );

    expect(uri, isNotNull);
    expect(uri!.origin, 'http://localhost:5173');
    expect(uri.path, '/try_on.html');
    expect(uri.queryParameters, {'mobileTryOn': 'true', 'frameId': '37'});
  });

  test('rejects insecure non-local Try-On origins', () {
    final uri = TryOnConfig.buildLaunchUri(
      frameId: 37,
      apiBaseUri: Uri.parse('https://api.gonzalesvisionclinic.com'),
      websiteOrigin: 'http://example.test',
    );

    expect(uri, isNull);
  });

  test('rejects unapproved API origins', () {
    final uri = TryOnConfig.buildLaunchUri(
      frameId: 37,
      apiBaseUri: Uri.parse('https://api.attacker.test'),
      websiteOrigin: 'https://portal.example.test',
    );

    expect(uri, isNull);
  });
}
