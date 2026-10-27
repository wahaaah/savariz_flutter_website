import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/responsive.dart';
import '../../app/theme.dart';
import '../../core/network/api_failure.dart';
import '../appointment_history/appointment_history_repository.dart';
import '../appointment_history/appointment_history_page.dart';
import '../appointment_history/appointment_history_record.dart';
import '../appointments/booking_page.dart';
import '../frames_catalog/frames_catalog_page.dart';
import '../frames_catalog/try_on_page.dart';
import '../profile/patient_profile_repository.dart';
import '../profile/profile_page.dart';
import '../transaction_history/transaction_history_page.dart';
import '../auth/application/patient_auth_scope.dart';
import '../auth/application/patient_auth_controller.dart';
import '../auth/domain/patient_session.dart';
import '../shell/portal_navigation.dart';
import '../shell/portal_shell.dart';
import '../support_center/support_center_page.dart';
import 'dashboard_appointment_summary.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    required this.isDark,
    required this.onToggleTheme,
    this.onLogout,
    this.logoutEnabled = false,
    this.dashboardAppointments,
    this.dashboardAppointmentsAsOf,
    super.key,
  });

  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback? onLogout;
  final bool logoutEnabled;
  final List<AppointmentHistoryRecord>? dashboardAppointments;
  final DateTime? dashboardAppointmentsAsOf;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  PortalDestination _selectedDestination = PortalDestination.dashboard;
  bool _focusAppointmentsSection = false;

  void _selectDestination(PortalDestination destination) {
    setState(() {
      _selectedDestination = destination;
      _focusAppointmentsSection = false;
    });
  }

  void _openMyAppointments() {
    setState(() {
      _selectedDestination = PortalDestination.appointments;
      _focusAppointmentsSection = true;
    });
  }

  void _openTryOn(Uri uri) {
    final size = MediaQuery.sizeOf(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: (size.width - 32).clamp(280.0, 920.0).toDouble(),
          height: (size.height - 48).clamp(360.0, 720.0).toDouble(),
          child: TryOnPage(uri: uri),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = PatientAuthScope.maybeOf(context);
    final session = controller?.currentSession;

    return PortalShell(
      selectedDestination: _selectedDestination,
      onSelectDestination: _selectDestination,
      isDark: widget.isDark,
      onToggleTheme: widget.onToggleTheme,
      onLogout: widget.onLogout,
      logoutEnabled: widget.logoutEnabled,
      child: switch (_selectedDestination) {
        PortalDestination.dashboard => _DashboardContent(
          onNavigate: _selectDestination,
          onOpenMyAppointments: _openMyAppointments,
          session: session,
          dashboardAppointments: widget.dashboardAppointments,
          dashboardAppointmentsAsOf: widget.dashboardAppointmentsAsOf,
        ),
        PortalDestination.appointments => BookingPage(
          focusMyAppointments: _focusAppointmentsSection,
        ),
        PortalDestination.appointmentHistory => const AppointmentHistoryPage(),
        PortalDestination.transactionHistory => const TransactionHistoryPage(),
        PortalDestination.framesCatalog => FramesCatalogPage(
          onOpenTryOn: _openTryOn,
        ),
        PortalDestination.supportCenter => const SupportCenterPage(),
        PortalDestination.profile => const ProfilePage(),
      },
    );
  }
}

class _DashboardContent extends StatefulWidget {
  const _DashboardContent({
    required this.onNavigate,
    required this.onOpenMyAppointments,
    required this.session,
    required this.dashboardAppointments,
    required this.dashboardAppointmentsAsOf,
  });

  final ValueChanged<PortalDestination> onNavigate;
  final VoidCallback onOpenMyAppointments;
  final PatientSession? session;
  final List<AppointmentHistoryRecord>? dashboardAppointments;
  final DateTime? dashboardAppointmentsAsOf;

  @override
  State<_DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends State<_DashboardContent> {
  PatientAuthController? _controller;
  AppointmentHistoryRepository? _appointmentRepository;
  PatientProfileRepository? _patientProfileRepository;
  List<AppointmentHistoryRecord>? _loadedAppointments;
  PatientProfileDetails? _patientDetails;
  String? _appointmentError;
  String? _patientDetailsError;
  String? _requestedSessionKey;
  String? _patientDetailsSessionKey;
  Timer? _appointmentRefreshTimer;
  Timer? _patientDetailsRefreshTimer;
  bool _isLoadingAppointments = false;
  bool _isLoadingPatientDetails = false;
  bool _appointmentRequestInFlight = false;
  bool _patientDetailsRequestInFlight = false;
  int _appointmentLoadGeneration = 0;
  int _patientDetailsLoadGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = PatientAuthScope.maybeOf(context);
    final repository = PatientAuthScope.appointmentsHistoryOf(context);
    final patientProfileRepository = PatientAuthScope.patientProfileOf(context);
    if (controller != _controller) {
      _controller?.removeListener(_handleSessionChanged);
      _controller = controller;
      _controller?.addListener(_handleSessionChanged);
      _requestedSessionKey = null;
      _patientDetailsSessionKey = null;
    }
    if (repository != _appointmentRepository) {
      _appointmentRepository = repository;
      _requestedSessionKey = null;
    }
    if (patientProfileRepository != _patientProfileRepository) {
      _patientProfileRepository = patientProfileRepository;
      _patientDetailsSessionKey = null;
    }
    _loadAppointments();
    _loadPatientDetails();
  }

  @override
  void dispose() {
    _appointmentLoadGeneration++;
    _patientDetailsLoadGeneration++;
    _appointmentRefreshTimer?.cancel();
    _patientDetailsRefreshTimer?.cancel();
    _controller?.removeListener(_handleSessionChanged);
    super.dispose();
  }

  void _handleSessionChanged() {
    _loadAppointments();
    _loadPatientDetails();
  }

  void _loadAppointments({bool force = false, bool silent = false}) {
    if (widget.dashboardAppointments != null) return;

    final repository = _appointmentRepository;
    final session = _controller?.currentSession;
    if (repository == null || session == null) {
      _appointmentRefreshTimer?.cancel();
      _appointmentRefreshTimer = null;
      _appointmentLoadGeneration++;
      _appointmentRequestInFlight = false;
      if (_loadedAppointments != null ||
          _appointmentError != null ||
          _isLoadingAppointments) {
        setState(() {
          _loadedAppointments = null;
          _appointmentError = null;
          _isLoadingAppointments = false;
        });
      }
      _requestedSessionKey = null;
      return;
    }

    final sessionKey = '${session.patientId}\u0000${session.token}';
    final isNewSession = sessionKey != _requestedSessionKey;
    if (!force && !isNewSession) return;
    if (_appointmentRequestInFlight && !isNewSession) return;

    _requestedSessionKey = sessionKey;
    final generation = ++_appointmentLoadGeneration;
    _appointmentRequestInFlight = true;
    setState(() {
      if (isNewSession) {
        _loadedAppointments = null;
      }
      if (!silent || _loadedAppointments == null) {
        _isLoadingAppointments = true;
      }
      _appointmentError = null;
    });

    _appointmentRefreshTimer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) => _loadAppointments(force: true, silent: true),
    );
    _fetchAppointments(repository, session, generation);
  }

  Future<void> _fetchAppointments(
    AppointmentHistoryRepository repository,
    PatientSession session,
    int generation,
  ) async {
    try {
      final appointments = await repository.getAppointments(
        patientId: session.patientId,
        token: session.token,
      );
      if (!mounted || generation != _appointmentLoadGeneration) return;
      setState(() {
        _loadedAppointments = appointments;
        _isLoadingAppointments = false;
        _appointmentError = null;
      });
    } on ApiFailure catch (failure) {
      if (!mounted || generation != _appointmentLoadGeneration) return;
      setState(() {
        _isLoadingAppointments = false;
        _appointmentError = failure.message;
      });
    } on Exception catch (error, stackTrace) {
      if (!mounted || generation != _appointmentLoadGeneration) return;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError(
            'Unexpected dashboard appointment failure '
            '(${error.runtimeType}).',
          ),
          stack: stackTrace,
          library: 'patient dashboard',
        ),
      );
      setState(() {
        _isLoadingAppointments = false;
        _appointmentError =
            'Your appointments could not be loaded. Please try again.';
      });
    } finally {
      if (generation == _appointmentLoadGeneration) {
        _appointmentRequestInFlight = false;
      }
    }
  }

  void _loadPatientDetails() {
    if (widget.dashboardAppointments != null) return;

    final repository = _patientProfileRepository;
    final session = _controller?.currentSession;
    if (repository == null || session == null) {
      _patientDetailsLoadGeneration++;
      _patientDetailsRequestInFlight = false;
      _patientDetailsRefreshTimer?.cancel();
      _patientDetailsRefreshTimer = null;
      _patientDetailsSessionKey = null;
      if (_patientDetails != null ||
          _patientDetailsError != null ||
          _isLoadingPatientDetails) {
        setState(() {
          _patientDetails = null;
          _patientDetailsError = null;
          _isLoadingPatientDetails = false;
        });
      }
      return;
    }

    final sessionKey = '${session.patientId}\u0000${session.token}';
    if (sessionKey == _patientDetailsSessionKey) return;
    _patientDetailsRefreshTimer?.cancel();
    _patientDetailsRequestInFlight = false;
    _patientDetailsSessionKey = sessionKey;
    final generation = ++_patientDetailsLoadGeneration;
    _patientDetailsRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshPatientDetails(),
    );
    setState(() {
      _patientDetails = null;
      _patientDetailsError = null;
      _isLoadingPatientDetails = true;
    });
    _fetchPatientDetails(repository, session, generation);
  }

  void _refreshPatientDetails() {
    if (_patientDetailsRequestInFlight) return;
    final repository = _patientProfileRepository;
    final session = _controller?.currentSession;
    if (repository == null || session == null) return;
    _fetchPatientDetails(repository, session, ++_patientDetailsLoadGeneration);
  }

  Future<void> _fetchPatientDetails(
    PatientProfileRepository repository,
    PatientSession session,
    int generation,
  ) async {
    if (_patientDetailsRequestInFlight) return;
    _patientDetailsRequestInFlight = true;
    try {
      final details = await repository.getPatientDetails(
        patientId: session.patientId,
        token: session.token,
      );
      if (!mounted || generation != _patientDetailsLoadGeneration) return;
      setState(() {
        _patientDetails = details;
        _isLoadingPatientDetails = false;
        _patientDetailsError = null;
      });
    } on ApiFailure catch (failure) {
      if (!mounted || generation != _patientDetailsLoadGeneration) return;
      setState(() {
        _isLoadingPatientDetails = false;
        _patientDetailsError = failure.message;
      });
    } on Exception catch (error, stackTrace) {
      if (!mounted || generation != _patientDetailsLoadGeneration) return;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError(
            'Unexpected dashboard patient-details failure '
            '(${error.runtimeType}).',
          ),
          stack: stackTrace,
          library: 'patient dashboard',
        ),
      );
      setState(() {
        _isLoadingPatientDetails = false;
        _patientDetailsError =
            'Your patient details could not be loaded. Please try again.';
      });
    } finally {
      if (generation == _patientDetailsLoadGeneration) {
        _patientDetailsRequestInFlight = false;
      }
    }
  }

  Future<void> _retryPatientDetails() async {
    _patientDetailsSessionKey = null;
    _loadPatientDetails();
  }

  @override
  Widget build(BuildContext context) {
    final records = widget.dashboardAppointments ?? _loadedAppointments;
    final appointmentSummary = records == null
        ? null
        : DashboardAppointmentSummary.fromRecords(
            records,
            now: widget.dashboardAppointmentsAsOf ?? DateTime.now(),
          );
    final secondary = Theme.of(context)
        .extension<PatientPortalTextColors>()!
        .secondary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = MediaQuery.sizeOf(context).width;
        final compact = viewportWidth <= PatientPortalBreakpoints.tablet;
        final narrow =
            viewportWidth <= PatientPortalBreakpoints.mobileNavigation;
        final singleColumnActions = viewportWidth <= 550;
        final pagePadding = narrow
            ? viewportWidth <= PatientPortalBreakpoints.mobile
                  ? 17.0
                  : 22.0
            : compact
            ? 25.0
            : 32.0;

        return SingleChildScrollView(
          padding: EdgeInsets.all(pagePadding),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: PatientPortalBreakpoints.contentMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Welcome back, ${_available(widget.session?.name)}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontSize: narrow ? 26 : 30,
                      height: 1.2,
                      letterSpacing: -1.05,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Manage your appointments and view your clinic '
                          'information from one place.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontSize: 14,
                                color: secondary,
                                height: 1.6,
                              ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                  SizedBox(height: narrow ? 20 : 28),
                  _SummaryCards(
                    narrow: narrow,
                    session: widget.session,
                    appointmentSummary: appointmentSummary,
                    isLoadingAppointments:
                        widget.dashboardAppointments == null &&
                        _isLoadingAppointments,
                    hasAppointmentError:
                        widget.dashboardAppointments == null &&
                        _appointmentError != null,
                  ),
                  const SizedBox(height: 20),
                  _MainDashboardCards(
                    compact: compact,
                    onNavigate: widget.onNavigate,
                    session: widget.session,
                    appointmentSummary: appointmentSummary,
                    isLoadingAppointments:
                        widget.dashboardAppointments == null &&
                        _isLoadingAppointments,
                    appointmentError: widget.dashboardAppointments == null
                        ? _appointmentError
                        : null,
                    onRetryAppointments: () async {
                      _loadAppointments(force: true);
                    },
                    patientDetails: _patientDetails,
                    isLoadingPatientDetails: _isLoadingPatientDetails,
                    patientDetailsError: _patientDetailsError,
                    onRetryPatientDetails: _retryPatientDetails,
                  ),
                  const SizedBox(height: 22),
                  _QuickActions(
                    narrow: singleColumnActions,
                    compact: compact,
                    onNavigate: widget.onNavigate,
                    onOpenMyAppointments: widget.onOpenMyAppointments,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({
    required this.narrow,
    required this.session,
    required this.appointmentSummary,
    required this.isLoadingAppointments,
    required this.hasAppointmentError,
  });

  final bool narrow;
  final PatientSession? session;
  final DashboardAppointmentSummary? appointmentSummary;
  final bool isLoadingAppointments;
  final bool hasAppointmentError;

  @override
  Widget build(BuildContext context) {
    final lastVisit = appointmentSummary?.latestPastAppointment?.scheduledAt;
    return LayoutBuilder(
      builder: (context, constraints) {
        final useSingleColumn = narrow || constraints.maxWidth < 560;
        final cardWidth = useSingleColumn
            ? constraints.maxWidth
            : (constraints.maxWidth - 32) / 3;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _SummaryCard(
              width: cardWidth,
              icon: Icons.calendar_month_outlined,
              title: 'Upcoming Appointments',
              value:
                  appointmentSummary?.upcomingCount.toString() ??
                  (isLoadingAppointments
                      ? 'Loading…'
                      : hasAppointmentError
                      ? '—'
                      : 'Unavailable'),
              detail: 'Scheduled visits',
            ),
            _SummaryCard(
              width: cardWidth,
              icon: Icons.event_available_outlined,
              title: 'Last Visit',
              value: lastVisit != null
                  ? formatDashboardAppointmentDate(lastVisit)
                  : isLoadingAppointments
                  ? 'Loading…'
                  : hasAppointmentError
                  ? '—'
                  : appointmentSummary != null
                  ? 'None'
                  : 'Unavailable',
              detail: 'Most recent clinic visit',
            ),
            _SummaryCard(
              width: cardWidth,
              icon: Icons.badge_outlined,
              title: 'Patient ID',
              value: _available(session?.patientId),
              detail: 'Your clinic identification number',
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.width,
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
  });

  final double width;
  final IconData icon;
  final String title;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;

    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(19),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color: secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _IconTile(icon: icon),
                ],
              ),
              const SizedBox(height: 17),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 22,
                  color: theme.colorScheme.onSurface,
                  letterSpacing: -0.44,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MainDashboardCards extends StatelessWidget {
  const _MainDashboardCards({
    required this.compact,
    required this.onNavigate,
    required this.session,
    required this.appointmentSummary,
    required this.isLoadingAppointments,
    required this.appointmentError,
    required this.onRetryAppointments,
    required this.patientDetails,
    required this.isLoadingPatientDetails,
    required this.patientDetailsError,
    required this.onRetryPatientDetails,
  });

  final bool compact;
  final ValueChanged<PortalDestination> onNavigate;
  final PatientSession? session;
  final DashboardAppointmentSummary? appointmentSummary;
  final bool isLoadingAppointments;
  final String? appointmentError;
  final Future<void> Function() onRetryAppointments;
  final PatientProfileDetails? patientDetails;
  final bool isLoadingPatientDetails;
  final String? patientDetailsError;
  final Future<void> Function() onRetryPatientDetails;

  @override
  Widget build(BuildContext context) {
    const gap = 18.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (compact || constraints.maxWidth < 700) {
          return Column(
            children: [
              _UpcomingAppointmentCard(
                onNavigate: onNavigate,
                appointmentSummary: appointmentSummary,
                isLoading: isLoadingAppointments,
                errorMessage: appointmentError,
                onRetry: onRetryAppointments,
              ),
              SizedBox(height: gap),
              _PatientInformationCard(
                session: session,
                details: patientDetails,
                isLoading: isLoadingPatientDetails,
                errorMessage: patientDetailsError,
                onRetry: onRetryPatientDetails,
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 13,
              child: _UpcomingAppointmentCard(
                onNavigate: onNavigate,
                appointmentSummary: appointmentSummary,
                isLoading: isLoadingAppointments,
                errorMessage: appointmentError,
                onRetry: onRetryAppointments,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              flex: 7,
              child: _PatientInformationCard(
                session: session,
                details: patientDetails,
                isLoading: isLoadingPatientDetails,
                errorMessage: patientDetailsError,
                onRetry: onRetryPatientDetails,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _UpcomingAppointmentCard extends StatelessWidget {
  const _UpcomingAppointmentCard({
    required this.onNavigate,
    required this.appointmentSummary,
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
  });

  final ValueChanged<PortalDestination> onNavigate;
  final DashboardAppointmentSummary? appointmentSummary;
  final bool isLoading;
  final String? errorMessage;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final secondary = theme.extension<PatientPortalTextColors>()!.secondary;

        return _SectionCard(
          title: 'Upcoming Appointment',
          subtitle: 'Your next scheduled visit',
          actionLabel: constraints.maxWidth > 400 ? 'View appointments' : null,
          onAction: () => onNavigate(PortalDestination.appointments),
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (appointmentSummary?.earliestAppointment
                      case final appointment?) ...[
                    _EmptyAppointmentIcon(color: secondary),
                    const SizedBox(height: 12),
                    Text(
                      formatDashboardAppointmentDate(appointment.scheduledAt!),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (formatDashboardAppointmentTime(appointment.time)
                        case final time?) ...[
                      const SizedBox(height: 5),
                      Text(
                        time,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                        ),
                      ),
                    ],
                    if (appointment.purpose case final purpose?) ...[
                      const SizedBox(height: 5),
                      Text(
                        purpose,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                        ),
                      ),
                    ],
                    if (appointment.status case final status?) ...[
                      const SizedBox(height: 5),
                      Text(
                        status,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                        ),
                      ),
                    ],
                  ] else ...[
                    _EmptyAppointmentIcon(color: secondary),
                    const SizedBox(height: 12),
                    Text(
                      isLoading
                          ? 'Loading appointments…'
                          : errorMessage != null
                          ? 'Appointments could not be loaded'
                          : appointmentSummary != null
                          ? 'No upcoming appointment'
                          : 'Appointment data unavailable',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      isLoading
                          ? 'Retrieving your latest appointment details.'
                          : errorMessage ??
                                (appointmentSummary != null
                                    ? 'Choose a date and time to schedule your next visit.'
                                    : 'The appointment service is not configured.'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color: secondary,
                      ),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => onRetry(),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Retry'),
                      ),
                    ],
                  ],
                  const SizedBox(height: 15),
                  FilledButton.icon(
                    onPressed: () => onNavigate(PortalDestination.appointments),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Book an appointment'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      textStyle: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyAppointmentIcon extends StatelessWidget {
  const _EmptyAppointmentIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.light
            ? const Color(0xFFF8FAFC)
            : const Color(0xFF162238),
        borderRadius: BorderRadius.circular(11),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.event_busy_outlined, size: 22, color: color),
    );
  }
}

class _PatientInformationCard extends StatelessWidget {
  const _PatientInformationCard({
    required this.session,
    required this.details,
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
  });

  final PatientSession? session;
  final PatientProfileDetails? details;
  final bool isLoading;
  final String? errorMessage;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Patient Information',
      subtitle: 'Your clinic account details',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          children: [
            _InformationRow(
              label: 'Full name',
              value: _available(session?.name),
              isFirst: true,
            ),
            _InformationRow(
              label: 'Patient ID',
              value: _available(session?.patientId),
            ),
            _InformationRow(
              label: 'Contact number',
              value: _profileValue(details?.contactNumber, isLoading),
            ),
            _InformationRow(label: 'Email', value: _available(session?.email)),
            _InformationRow(
              label: 'Address',
              value: _profileValue(details?.address, isLoading),
              isLast: true,
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  errorMessage!,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry patient details'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _available(String? value) =>
    value == null || value.trim().isEmpty ? 'Unavailable' : value;

String _profileValue(String? value, bool isLoading) {
  if (value != null && value.trim().isNotEmpty) return value;
  return isLoading ? 'Loading…' : 'Unavailable';
}

class _InformationRow extends StatelessWidget {
  const _InformationRow({
    required this.label,
    required this.value,
    this.isFirst = false,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context)
        .extension<PatientPortalTextColors>()!
        .secondary;
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: isFirst ? 0 : 13,
            bottom: isLast ? 0 : 13,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 112,
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  softWrap: true,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!isLast) Divider(height: 1, color: theme.colorScheme.outline),
      ],
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.narrow,
    required this.compact,
    required this.onNavigate,
    required this.onOpenMyAppointments,
  });

  final bool narrow;
  final bool compact;
  final ValueChanged<PortalDestination> onNavigate;
  final VoidCallback onOpenMyAppointments;

  static const _actions = <_QuickActionData>[
    _QuickActionData(
      title: 'Book an Appointment',
      description: 'Choose a convenient date and time.',
      icon: Icons.add_circle_outline,
      destination: PortalDestination.appointments,
    ),
    _QuickActionData(
      title: 'My Appointments',
      description: 'View your appointment history.',
      icon: Icons.calendar_month_outlined,
      destination: PortalDestination.appointments,
      focusMyAppointments: true,
    ),
    _QuickActionData(
      title: 'Appointment History',
      description: 'View your previous and completed appointments.',
      icon: Icons.history,
      destination: PortalDestination.appointmentHistory,
    ),
    _QuickActionData(
      title: 'Transaction History',
      description: 'View your clinic payments and purchase records.',
      icon: Icons.receipt_long_outlined,
      destination: PortalDestination.transactionHistory,
    ),
    _QuickActionData(
      title: 'Frames Catalog',
      description: 'Browse available frames.',
      icon: Icons.visibility_outlined,
      destination: PortalDestination.framesCatalog,
    ),
    _QuickActionData(
      title: 'My Profile',
      description: 'View your patient information.',
      icon: Icons.person_outline,
      destination: PortalDestination.profile,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Quick Actions',
      subtitle: 'Access the most commonly used patient portal features.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = (constraints.maxWidth - 40)
              .clamp(0.0, constraints.maxWidth)
              .toDouble();
          const spacing = 16.0;
          final columns = narrow || availableWidth < 480
              ? 1
              : compact || availableWidth < 760
              ? 2
              : 4;
          final width = ((availableWidth - spacing * (columns - 1)) / columns)
              .clamp(0.0, availableWidth)
              .toDouble();

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: _actions
                  .map(
                    (action) => SizedBox(
                      width: width,
                      child: _QuickActionCard(
                        action: action,
                        onTap: action.focusMyAppointments
                            ? onOpenMyAppointments
                            : () => onNavigate(action.destination),
                      ),
                    ),
                  )
                  .toList(),
            ),
          );
        },
      ),
    );
  }
}

class _QuickActionData {
  const _QuickActionData({
    required this.title,
    required this.description,
    required this.icon,
    required this.destination,
    this.focusMyAppointments = false,
  });

  final String title;
  final String description;
  final IconData icon;
  final PortalDestination destination;
  final bool focusMyAppointments;
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({required this.action, required this.onTap});

  final _QuickActionData action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;

    return Semantics(
      button: true,
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 106),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IconTile(icon: action.icon, size: 36),
                const SizedBox(height: 13),
                Text(
                  action.title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  action.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: secondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 68,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.24,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            color: secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: onAction,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        side: BorderSide(color: theme.colorScheme.outline),
                        foregroundColor: secondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                        textStyle: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outline),
          child,
        ],
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, this.size = 38});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final background = theme.brightness == Brightness.light
        ? const Color(0xFFEFF6FF)
        : const Color(0xFF122C58);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size == 36 ? 9 : 10),
      ),
      child: Icon(icon, color: primary, size: 20),
    );
  }
}
