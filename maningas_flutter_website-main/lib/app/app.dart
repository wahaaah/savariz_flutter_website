import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/config/api_config.dart';
import '../core/network/api_client.dart';
import '../core/network/api_failure.dart';
import '../features/auth/application/patient_auth_controller.dart';
import '../features/auth/application/patient_auth_scope.dart';
import '../features/auth/application/patient_auth_setup.dart';
import '../features/appointment_history/appointment_history_repository.dart';
import '../features/frames_catalog/frames_catalog_repository.dart';
import '../features/auth/login_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/profile/patient_profile_repository.dart';
import '../features/shell/notification_repository.dart';
import '../features/transaction_history/transaction_history_repository.dart';
import '../features/support_center/support_center_repository.dart';
import 'theme.dart';

class PatientPortalApp extends StatefulWidget {
  const PatientPortalApp({this.setup, this.controller, super.key})
    : assert(setup == null || controller == null);

  final PatientAuthSetup? setup;
  final PatientAuthController? controller;
  @override
  State<PatientPortalApp> createState() => _PatientPortalAppState();
}

class _PatientPortalAppState extends State<PatientPortalApp>
    with WidgetsBindingObserver {
  static const _sessionRefreshInterval = Duration(hours: 12);

  ThemeMode _themeMode = ThemeMode.light;
  bool _isLoggingOut = false;
  Timer? _sessionRefreshTimer;
  late final PatientAuthController _controller;
  late final bool _ownsController;
  late final FramesCatalogRepository _framesCatalogRepository;
  late final NotificationRepository _notificationRepository;
  late final TransactionHistoryRepository _transactionHistoryRepository;
  late final AppointmentHistoryRepository _appointmentHistoryRepository;
  late final PatientProfileRepository _patientProfileRepository;
  late final SupportCenterRepository _supportCenterRepository;
  ApiClient? _ownedApiClient;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final setup =
        widget.setup ??
        (widget.controller == null ? createPatientAuthSetup() : null);
    _ownsController = setup != null;
    if (setup != null) {
      _controller = setup.controller;
      _framesCatalogRepository = setup.framesCatalogRepository;
      _notificationRepository = setup.notificationRepository;
      _transactionHistoryRepository = setup.transactionHistoryRepository;
      _appointmentHistoryRepository = setup.appointmentHistoryRepository;
      _patientProfileRepository = setup.patientProfileRepository;
      _supportCenterRepository = setup.supportCenterRepository;
    } else {
      _controller = widget.controller!;
      final apiClient = ApiClient(
        client: http.Client(),
        baseUri: ApiConfig.baseUri,
      );
      _ownedApiClient = apiClient;
      _framesCatalogRepository = ApiFramesCatalogRepository(apiClient);
      _notificationRepository = ApiNotificationRepository(apiClient);
      _transactionHistoryRepository = ApiTransactionHistoryRepository(
        apiClient,
      );
      _appointmentHistoryRepository = ApiAppointmentHistoryRepository(
        apiClient,
      );
      _patientProfileRepository = ApiPatientProfileRepository(apiClient);
      _supportCenterRepository = ApiSupportCenterRepository(apiClient);
    }
    if (_controller.currentSession != null) {
      unawaited(_controller.loadCurrentPatientIdentity());
    }
    if (kIsWeb) {
      _sessionRefreshTimer = Timer.periodic(
        _sessionRefreshInterval,
        (_) => unawaited(_refreshSession()),
      );
    }
  }

  @override
  void dispose() {
    _sessionRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsController) _controller.dispose();
    if (!_ownsController) _ownedApiClient?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb && state == AppLifecycleState.resumed) {
      unawaited(_refreshSession());
    }
  }

  Future<void> _refreshSession() async {
    if (!mounted ||
        _controller.currentSession == null ||
        _controller.isLoadingIdentity) {
      return;
    }
    try {
      await _controller.validateCurrentSession();
    } on ApiFailure catch (failure) {
      debugPrint('Unable to refresh patient session: ${failure.message}');
    }
  }

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.light
          ? ThemeMode.dark
          : ThemeMode.light;
    });
  }

  Future<void> _logout() async {
    setState(() => _isLoggingOut = true);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    _controller.logout();
    setState(() {
      _themeMode = ThemeMode.light;
      _isLoggingOut = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PatientAuthScope(
      controller: _controller,
      framesCatalogRepository: _framesCatalogRepository,
      notificationRepository: _notificationRepository,
      transactionHistoryRepository: _transactionHistoryRepository,
      appointmentHistoryRepository: _appointmentHistoryRepository,
      patientProfileRepository: _patientProfileRepository,
      supportCenterRepository: _supportCenterRepository,
      child: MaterialApp(
        title: 'Gonzales Vision Clinic Patient Portal',
        debugShowCheckedModeBanner: false,
        theme: PatientPortalTheme.light,
        darkTheme: PatientPortalTheme.dark,
        themeMode: _themeMode,
        home: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                if (_controller.isLoadingIdentity) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                final authenticated = _controller.currentSession != null;
                if (!authenticated) {
                  return Theme(
                    data: PatientPortalTheme.light,
                    child: LoginPage(controller: _controller),
                  );
                }
                return DashboardPage(
                  isDark: _themeMode == ThemeMode.dark,
                  onToggleTheme: _toggleTheme,
                  onLogout: _logout,
                  logoutEnabled: authenticated,
                );
              },
            ),
            if (_isLoggingOut)
              ColoredBox(
                color: const Color(0xCC0F172A),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      Text(
                        'Logging out…',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
