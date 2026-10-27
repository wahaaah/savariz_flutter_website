import 'package:flutter/widgets.dart';

import '../../frames_catalog/frames_catalog_repository.dart';
import '../../appointment_history/appointment_history_repository.dart';
import '../../profile/patient_profile_repository.dart';
import '../../shell/notification_repository.dart';
import '../../transaction_history/transaction_history_repository.dart';
import '../../support_center/support_center_repository.dart';
import 'patient_auth_controller.dart';

class PatientAuthScope extends InheritedWidget {
  const PatientAuthScope({
    required this.controller,
    this.framesCatalogRepository,
    this.notificationRepository,
    this.transactionHistoryRepository,
    this.appointmentHistoryRepository,
    this.patientProfileRepository,
    this.supportCenterRepository,
    required super.child,
    super.key,
  });

  final PatientAuthController controller;
  final FramesCatalogRepository? framesCatalogRepository;
  final NotificationRepository? notificationRepository;
  final TransactionHistoryRepository? transactionHistoryRepository;
  final AppointmentHistoryRepository? appointmentHistoryRepository;
  final PatientProfileRepository? patientProfileRepository;
  final SupportCenterRepository? supportCenterRepository;

  static PatientAuthController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<PatientAuthScope>()
        ?.controller;
  }

  static FramesCatalogRepository? framesCatalogOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<PatientAuthScope>()
        ?.framesCatalogRepository;
  }

  static NotificationRepository? notificationsOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<PatientAuthScope>()
        ?.notificationRepository;
  }

  static TransactionHistoryRepository? transactionsOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<PatientAuthScope>()
        ?.transactionHistoryRepository;
  }

  static AppointmentHistoryRepository? appointmentsHistoryOf(
    BuildContext context,
  ) {
    return context
        .dependOnInheritedWidgetOfExactType<PatientAuthScope>()
        ?.appointmentHistoryRepository;
  }

  static PatientProfileRepository? patientProfileOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<PatientAuthScope>()
        ?.patientProfileRepository;
  }

  static SupportCenterRepository? supportCenterOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<PatientAuthScope>()
        ?.supportCenterRepository;
  }

  @override
  bool updateShouldNotify(PatientAuthScope oldWidget) =>
      controller != oldWidget.controller ||
      framesCatalogRepository != oldWidget.framesCatalogRepository ||
      notificationRepository != oldWidget.notificationRepository ||
      transactionHistoryRepository != oldWidget.transactionHistoryRepository ||
      appointmentHistoryRepository != oldWidget.appointmentHistoryRepository ||
      patientProfileRepository != oldWidget.patientProfileRepository ||
      supportCenterRepository != oldWidget.supportCenterRepository;
}
