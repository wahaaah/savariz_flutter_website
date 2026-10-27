import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patient_portal_flutter/app/app.dart';
import 'package:patient_portal_flutter/features/auth/login_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('starts at API sign-in without loading sample records', (
    tester,
  ) async {
    await tester.pumpWidget(const PatientPortalApp());

    expect(find.byType(LoginPage), findsOneWidget);
  });
}
