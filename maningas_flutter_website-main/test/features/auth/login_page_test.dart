import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patient_portal_flutter/app/app.dart';
import 'package:patient_portal_flutter/features/dashboard/dashboard_page.dart';
import 'package:patient_portal_flutter/features/appointment_history/appointment_history_record.dart';
import 'package:patient_portal_flutter/features/appointment_history/appointment_history_repository.dart';
import 'package:patient_portal_flutter/features/appointments/booking_schedule.dart';
import 'package:patient_portal_flutter/features/auth/application/patient_auth_controller.dart';
import 'package:patient_portal_flutter/features/auth/application/patient_auth_setup.dart';
import 'package:patient_portal_flutter/features/auth/data/patient_auth_repository.dart';
import 'package:patient_portal_flutter/features/auth/domain/patient_registration.dart';
import 'package:patient_portal_flutter/features/auth/domain/patient_session.dart';
import 'package:patient_portal_flutter/features/auth/domain/patient_session_store.dart';
import 'package:patient_portal_flutter/features/frames_catalog/catalog_frame.dart';
import 'package:patient_portal_flutter/features/frames_catalog/frames_catalog_repository.dart';
import 'package:patient_portal_flutter/features/profile/patient_profile_repository.dart';
import 'package:patient_portal_flutter/features/shell/notification_repository.dart';
import 'package:patient_portal_flutter/features/shell/patient_notification.dart';
import 'package:patient_portal_flutter/features/support_center/support_center_repository.dart';
import 'package:patient_portal_flutter/features/support_center/support_ticket.dart';
import 'package:patient_portal_flutter/features/transaction_history/transaction_history_repository.dart';
import 'package:patient_portal_flutter/features/transaction_history/transaction_record.dart';
import 'package:patient_portal_flutter/core/network/api_failure.dart';

void main() {
  testWidgets('clears a rejected password and keeps the login form available', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final authRepository = _FakeAuthRepository(rejectLogin: true);
    await tester.pumpWidget(_app(authRepository));

    await tester.enterText(
      find.byKey(const ValueKey('login-Email Address')),
      'patient@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login-Password')),
      'incorrect-password',
    );
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('login-submit')))
        .onPressed!();
    await tester.pump();
    await tester.pump();

    final passwordField = tester.widget<TextField>(
      find.byKey(const ValueKey('login-Password')),
    );
    expect(passwordField.controller!.text, isEmpty);
    expect(find.text('Invalid email or password.'), findsOneWidget);
    expect(find.byKey(const ValueKey('login-submit')), findsOneWidget);
  });

  testWidgets('shows the dashboard after successful sign-in', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(_FakeAuthRepository()));

    await tester.enterText(
      find.byKey(const ValueKey('login-Email Address')),
      'patient@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login-Password')),
      'correct-password',
    );
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('login-submit')))
        .onPressed!();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.byType(DashboardPage), findsOneWidget);
  });
}

Widget _app(_FakeAuthRepository authRepository) {
  return PatientPortalApp(
    setup: PatientAuthSetup(
      controller: PatientAuthController(
        repository: authRepository,
        sessionStore: InMemoryPatientSessionStore(),
      ),
      framesCatalogRepository: _FakeFramesCatalogRepository(),
      notificationRepository: _FakeNotificationRepository(),
      transactionHistoryRepository: _FakeTransactionHistoryRepository(),
      appointmentHistoryRepository: _FakeAppointmentHistoryRepository(),
      patientProfileRepository: _FakePatientProfileRepository(),
      supportCenterRepository: _FakeSupportCenterRepository(),
    ),
  );
}

class _FakeAuthRepository implements PatientAuthRepository {
  _FakeAuthRepository({this.rejectLogin = false});

  final bool rejectLogin;

  @override
  Future<PatientAuthResult> login({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    if (rejectLogin) {
      throw const ApiFailure(
        kind: ApiFailureKind.http,
        statusCode: 401,
        message: 'Invalid email or password.',
      );
    }
    return PatientAuthResult.api(
      PatientSession(
        patientId: 'patient-1',
        name: 'Test Patient',
        email: email,
        token: 'test-token',
        rememberMe: rememberMe,
      ),
    );
  }

  @override
  Future<PatientSession> validateSession(String token) async => PatientSession(
    patientId: 'patient-1',
    name: 'Test Patient',
    email: 'patient@example.com',
    token: token,
    rememberMe: false,
  );

  @override
  Future<PatientRegistrationResult> register(
    PatientRegistrationRequest request,
  ) => throw UnimplementedError();

  @override
  Future<EmailVerificationResult> verifyEmail({
    required String email,
    required String otp,
  }) => throw UnimplementedError();

  @override
  Future<ResendVerificationResult> resendVerification({
    required String email,
  }) => throw UnimplementedError();

  @override
  Future<String> requestPasswordReset({required String email}) =>
      throw UnimplementedError();

  @override
  Future<String> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) => throw UnimplementedError();
}

class _FakeAppointmentHistoryRepository
    implements AppointmentHistoryRepository {
  @override
  Future<List<AppointmentHistoryRecord>> getAppointments({
    required String patientId,
    required String token,
  }) async => [];

  @override
  Future<BookingSchedule> getBookingSchedule({required String token}) async =>
      const BookingSchedule();

  @override
  Future<String> createAppointment({
    required String patientId,
    required String token,
    required DateTime date,
    required String time,
    required String purpose,
  }) async => '';

  @override
  Future<String> cancelAppointment({
    required String patientId,
    required String token,
    required String appointmentId,
  }) async => '';
}

class _FakeFramesCatalogRepository implements FramesCatalogRepository {
  @override
  Future<List<CatalogFrame>> getFrames() async => [];
}

class _FakeNotificationRepository implements NotificationRepository {
  @override
  Future<List<PatientNotification>> getNotifications({
    required String patientId,
    required String token,
  }) async => [];

  @override
  Future<int> getUnreadCount({
    required String patientId,
    required String token,
  }) async => 0;

  @override
  Future<void> markAsRead({
    required int notificationId,
    required String token,
  }) async {}

  @override
  Future<void> markAllAsRead({
    required String patientId,
    required String token,
  }) async {}
}

class _FakeTransactionHistoryRepository
    implements TransactionHistoryRepository {
  @override
  Future<List<TransactionRecord>> getTransactions({
    required String patientId,
    required String token,
  }) async => [];
}

class _FakePatientProfileRepository implements PatientProfileRepository {
  @override
  Future<PatientProfileDetails> getPatientDetails({
    required String patientId,
    required String token,
  }) async => const PatientProfileDetails();
}

class _FakeSupportCenterRepository implements SupportCenterRepository {
  @override
  Future<List<SupportTicket>> getMyTickets({
    required String patientId,
    required String token,
  }) async => [];

  @override
  Future<List<SupportMessage>> getMessages({
    required String patientId,
    required String token,
    required String ticketId,
  }) async => [];

  @override
  Future<SupportTicket?> createTicket({
    required String patientId,
    required String token,
    required String category,
    required String subject,
    required String description,
    required String priority,
  }) async => null;

  @override
  Future<void> cancelTicket({
    required String token,
    required String ticketId,
  }) async {}

  @override
  Future<void> sendMessage({
    required String token,
    required String ticketId,
    required String message,
  }) async {}

  @override
  Future<void> markMessagesRead({
    required String token,
    required String ticketId,
  }) async {}
}
