import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/network/api_client.dart';
import '../../appointment_history/appointment_history_repository.dart';
import '../data/patient_auth_api_repository.dart';
import '../domain/patient_session_store.dart';
import '../domain/patient_session_store_stub.dart'
    if (dart.library.js_interop) '../domain/patient_session_store_web.dart'
    as session_store;
import 'patient_auth_controller.dart';
import '../../frames_catalog/frames_catalog_repository.dart';
import '../../profile/patient_profile_repository.dart';
import '../../shell/notification_repository.dart';
import '../../transaction_history/transaction_history_repository.dart';
import '../../support_center/support_center_repository.dart';

class PatientAuthSetup {
  const PatientAuthSetup({
    required this.controller,
    required this.framesCatalogRepository,
    required this.notificationRepository,
    required this.transactionHistoryRepository,
    required this.appointmentHistoryRepository,
    required this.patientProfileRepository,
    required this.supportCenterRepository,
  });

  final PatientAuthController controller;
  final FramesCatalogRepository framesCatalogRepository;
  final NotificationRepository notificationRepository;
  final TransactionHistoryRepository transactionHistoryRepository;
  final AppointmentHistoryRepository appointmentHistoryRepository;
  final PatientProfileRepository patientProfileRepository;
  final SupportCenterRepository supportCenterRepository;
}

PatientAuthSetup createPatientAuthSetup() {
  final PatientSessionStore sessionStore =
      session_store.createPatientSessionStore();
  final apiClient = ApiClient(
    client: http.Client(),
    baseUri: ApiConfig.baseUri,
  );
  return PatientAuthSetup(
    controller: PatientAuthController(
      repository: PatientAuthApiRepository(apiClient),
      sessionStore: sessionStore,
      onDispose: apiClient.close,
    ),
    framesCatalogRepository: ApiFramesCatalogRepository(apiClient),
    notificationRepository: ApiNotificationRepository(apiClient),
    transactionHistoryRepository: ApiTransactionHistoryRepository(apiClient),
    appointmentHistoryRepository: ApiAppointmentHistoryRepository(apiClient),
    patientProfileRepository: ApiPatientProfileRepository(apiClient),
    supportCenterRepository: ApiSupportCenterRepository(apiClient),
  );
}

PatientAuthController createPatientAuthController() =>
    createPatientAuthSetup().controller;
