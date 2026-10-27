import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/responsive.dart';
import '../../app/theme.dart';
import '../../core/network/api_failure.dart';
import '../auth/application/patient_auth_controller.dart';
import '../auth/application/patient_auth_scope.dart';
import '../auth/domain/patient_session.dart';
import 'change_password_page.dart';
import 'edit_profile_page.dart';
import 'patient_profile_repository.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  PatientAuthController? _controller;
  PatientProfileRepository? _profileRepository;
  PatientProfileDetails? _details;
  String? _detailsError;
  String? _detailsSessionKey;
  Timer? _detailsRefreshTimer;
  bool _isLoadingDetails = false;
  bool _detailsRequestInProgress = false;
  int _detailsLoadGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = PatientAuthScope.maybeOf(context);
    final repository = PatientAuthScope.patientProfileOf(context);
    if (controller != _controller) {
      _controller?.removeListener(_onControllerChanged);
      _controller = controller;
      _controller?.addListener(_onControllerChanged);
      _detailsSessionKey = null;
      if (controller != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && identical(_controller, controller)) {
            unawaited(controller.loadCurrentPatientIdentity());
          }
        });
      }
    }
    if (repository != _profileRepository) {
      _profileRepository = repository;
      _detailsSessionKey = null;
    }
    _loadPatientDetails();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    _loadPatientDetails();
  }

  @override
  void dispose() {
    _detailsLoadGeneration++;
    _detailsRequestInProgress = false;
    _detailsRefreshTimer?.cancel();
    _detailsRequestInProgress = false;
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final session = controller?.currentSession;
    final identityConfirmed = session?.status != null;
    const unavailable =
        'Unavailable — not returned by the authenticated profile service';
    final waiting = controller?.isLoadingIdentity ?? false;
    final identityFailure = controller?.identityFailure;
    final patientName = identityConfirmed
        ? session!.name
        : waiting
        ? 'Loading patient identity…'
        : unavailable;
    final displayName = _details?.fullName ?? patientName;
    final patientId = identityConfirmed
        ? session!.patientId
        : waiting
        ? 'Loading…'
        : unavailable;
    final email = identityConfirmed
        ? session!.email
        : waiting
        ? 'Loading…'
        : unavailable;
    final emailVerification = identityConfirmed
        ? session!.emailVerified == true
              ? 'Verified'
              : 'Not verified'
        : waiting
        ? 'Loading…'
        : unavailable;
    final accountStatus = identityConfirmed
        ? session!.status!
        : waiting
        ? 'Loading account status…'
        : 'Unavailable';
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final narrow = viewportWidth <= PatientPortalBreakpoints.mobile;
    final compact = viewportWidth <= PatientPortalBreakpoints.mobileNavigation;
    final pagePadding = narrow
        ? 17.0
        : compact
        ? 22.0
        : 30.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth - pagePadding * 2 < 850;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            pagePadding,
            compact ? 24 : 30,
            pagePadding,
            compact ? 35 : 45,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1250),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PageHeader(
                    compact: compact,
                    onEdit: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => EditProfilePage(
                            initialDetails: _details,
                            initialName:
                                _details?.fullName ??
                                _controller?.currentSession?.name,
                          ),
                        ),
                      );
                    },
                    onChangePassword: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ChangePasswordPage(),
                        ),
                      );
                    },
                  ),
                  if (waiting) ...[
                    const SizedBox(height: 14),
                    const LinearProgressIndicator(
                      key: ValueKey('profile-identity-loading'),
                    ),
                  ],
                  if (identityFailure != null) ...[
                    const SizedBox(height: 14),
                    _IdentityError(
                      message: identityFailure.message,
                      onRetry: controller == null
                          ? null
                          : () => unawaited(
                              controller.loadCurrentPatientIdentity(),
                            ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _ProfileHero(name: displayName, status: accountStatus),
                  const SizedBox(height: 20),
                  if (stacked)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ProfileLeftColumn(
                          name: displayName,
                          patientId: patientId,
                          email: _details?.email ?? email,
                          emailVerification: emailVerification,
                          details: _details,
                          detailsLoading: _isLoadingDetails,
                        ),
                        SizedBox(height: 20),
                        _ProfileRightColumn(
                          patientId: patientId,
                          status: accountStatus,
                        ),
                      ],
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: _ProfileLeftColumn(
                            name: displayName,
                            patientId: patientId,
                            email: _details?.email ?? email,
                            emailVerification: emailVerification,
                            details: _details,
                            detailsLoading: _isLoadingDetails,
                          ),
                        ),
                        SizedBox(width: 20),
                        Expanded(
                          flex: 3,
                          child: _ProfileRightColumn(
                            patientId: patientId,
                            status: accountStatus,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 20),
                  if (_detailsError != null) ...[
                    _IdentityError(
                      message: _detailsError!,
                      onRetry: _profileRepository == null
                          ? null
                          : () => _retryPatientDetails(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const _PrivacyNotice(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _loadPatientDetails({bool refresh = false}) {
    final repository = _profileRepository;
    final session = _controller?.currentSession;
    if (repository == null || session == null) {
      _detailsLoadGeneration++;
      _detailsRequestInProgress = false;
      _detailsRefreshTimer?.cancel();
      _detailsRefreshTimer = null;
      _detailsSessionKey = null;
      if (_details != null || _detailsError != null || _isLoadingDetails) {
        setState(() {
          _details = null;
          _detailsError = null;
          _isLoadingDetails = false;
        });
      }
      return;
    }

    final key = '${session.patientId}\u0000${session.token}';
    if (_detailsSessionKey == key) {
      if (refresh) {
        _fetchPatientDetails(repository, session, _detailsLoadGeneration);
      }
      return;
    }
    _detailsRefreshTimer?.cancel();
    _detailsRequestInProgress = false;
    _detailsSessionKey = key;
    final generation = ++_detailsLoadGeneration;
    _detailsRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadPatientDetails(refresh: true),
    );
    setState(() {
      _details = null;
      _detailsError = null;
      _isLoadingDetails = true;
    });
    _fetchPatientDetails(repository, session, generation);
  }

  Future<void> _fetchPatientDetails(
    PatientProfileRepository repository,
    PatientSession session,
    int generation,
  ) async {
    if (_detailsRequestInProgress) return;
    _detailsRequestInProgress = true;
    try {
      final details = await repository.getPatientDetails(
        patientId: session.patientId,
        token: session.token,
      );
      if (!mounted || generation != _detailsLoadGeneration) return;
      setState(() {
        _details = details;
        _isLoadingDetails = false;
        _detailsError = null;
      });
    } on ApiFailure catch (failure) {
      if (!mounted || generation != _detailsLoadGeneration) return;
      setState(() {
        _isLoadingDetails = false;
        _detailsError = failure.message;
      });
    } on Exception catch (error, stackTrace) {
      if (!mounted || generation != _detailsLoadGeneration) return;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError(
            'Unexpected profile-details failure (${error.runtimeType}).',
          ),
          stack: stackTrace,
          library: 'patient profile',
        ),
      );
      setState(() {
        _isLoadingDetails = false;
        _detailsError =
            'Your profile details could not be loaded. Please try again.';
      });
    } finally {
      if (generation == _detailsLoadGeneration) {
        _detailsRequestInProgress = false;
      }
    }
  }

  Future<void> _retryPatientDetails() async {
    _detailsSessionKey = null;
    _loadPatientDetails();
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.compact,
    required this.onEdit,
    required this.onChangePassword,
  });

  final bool compact;
  final VoidCallback onEdit;
  final VoidCallback onChangePassword;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _PrimaryDot(),
            const SizedBox(width: 8),
            Text(
              'GONZALES VISION CLINIC',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My Profile',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontSize: compact ? 27 : 30,
                      height: 1.2,
                      letterSpacing: -0.9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'View your personal information and clinic account details.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: secondary,
                      fontSize: 15,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
          ],
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('profile-edit-action'),
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('Edit Profile'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('profile-change-password-action'),
                onPressed: onChangePassword,
                icon: const Icon(Icons.lock_outline_rounded, size: 17),
                label: const Text('Change Password'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.name, required this.status});

  final String name;
  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;
    final primarySoft = theme.brightness == Brightness.light
        ? const Color(0xFFEFF6FF)
        : const Color(0xFF122C58);
    final primaryBorder = theme.brightness == Brightness.light
        ? const Color(0xFFBFDBFE)
        : const Color(0xFF244F91);
    final heroName = name;
    final initial =
        heroName.isEmpty ||
            heroName.startsWith('Unavailable') ||
            heroName.startsWith('Loading')
        ? '?'
        : heroName.substring(0, 1).toUpperCase();

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primarySoft, theme.colorScheme.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.light ? 0.035 : 0.12,
            ),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(height: 4, color: theme.colorScheme.primary),
          ),
          Padding(
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width <=
                      PatientPortalBreakpoints.mobile
                  ? 21
                  : 24,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final vertical = constraints.maxWidth < 440;
                final avatar = Container(
                  width: vertical ? 60 : 72,
                  height: vertical ? 60 : 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: primaryBorder),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.08,
                        ),
                        blurRadius: 15,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    initial,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontSize: vertical ? 22 : 25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                );
                final summary = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      heroName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontSize: 21,
                        height: 1.3,
                        letterSpacing: -0.4,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Gonzales Vision Clinic patient',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 11),
                    _PatientStatus(label: status),
                  ],
                );

                if (vertical) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [avatar, const SizedBox(height: 14), summary],
                  );
                }
                return Row(
                  children: [
                    avatar,
                    const SizedBox(width: 18),
                    Expanded(child: summary),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileLeftColumn extends StatelessWidget {
  const _ProfileLeftColumn({
    required this.name,
    required this.patientId,
    required this.email,
    required this.emailVerification,
    required this.details,
    required this.detailsLoading,
  });

  final String name;
  final String patientId;
  final String email;
  final String emailVerification;
  final PatientProfileDetails? details;
  final bool detailsLoading;

  String _detail(String? value) => value?.trim().isNotEmpty == true
      ? value!
      : detailsLoading
      ? 'Loading…'
      : 'Not provided';

  bool get _hasStructuredAddress =>
      details?.addressUnit != null ||
      details?.street != null ||
      details?.barangay != null ||
      details?.cityMunicipality != null ||
      details?.province != null ||
      details?.zipCode != null;

  String _formattedDateOfBirth() {
    final value = details?.dateOfBirth;
    if (value == null || value.trim().isEmpty) return _detail(null);
    final date = _parseProfileDate(value);
    if (date == null) return _detail(null);
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _age() {
    final dateText = details?.dateOfBirth;
    if (dateText == null) return _detail(null);
    final date = _parseProfileDate(dateText);
    if (date == null) return _detail(null);
    final today = DateTime.now();
    var age = today.year - date.year;
    if (today.month < date.month ||
        (today.month == date.month && today.day < date.day)) {
      age--;
    }
    return age >= 0 ? '$age years old' : _detail(null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileCard(
          title: 'Personal Information',
          description: 'Your basic patient information',
          icon: Icons.person_outline,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InformationRow(label: 'Full name', value: name),
              _InformationRow(
                label: 'Date of birth',
                value: _formattedDateOfBirth(),
              ),
              _InformationRow(label: 'Age', value: _age()),
              _InformationRow(label: 'Gender', value: _detail(details?.gender)),
              _InformationRow(
                label: 'Patient ID',
                value: patientId,
                last: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _ProfileCard(
          title: 'Address Information',
          description: 'Your current residential address',
          icon: Icons.location_on_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_hasStructuredAddress)
                _InformationRow(
                  label: 'Address',
                  value: _detail(details?.address),
                  last: true,
                )
              else ...[
                _InformationRow(
                  label: 'House / Unit / Lot / Block',
                  value: _detail(details?.addressUnit),
                ),
                _InformationRow(
                  label: 'Street',
                  value: _detail(details?.street),
                ),
                _InformationRow(
                  label: 'Barangay',
                  value: _detail(details?.barangay),
                ),
                _InformationRow(
                  label: 'City / Municipality',
                  value: _detail(details?.cityMunicipality),
                ),
                _InformationRow(
                  label: 'Province',
                  value: _detail(details?.province),
                ),
                _InformationRow(
                  label: 'ZIP Code',
                  value: _detail(details?.zipCode),
                  last: true,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        _ProfileCard(
          title: 'Contact Information',
          description: 'Contact details associated with your account',
          icon: Icons.mail_outline,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InformationRow(
                label: 'Mobile / Contact number',
                value: _detail(details?.contactNumber),
              ),
              _InformationRow(label: 'Email address', value: email),
              _InformationRow(
                label: 'Email verification',
                value: emailVerification,
                last: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileRightColumn extends StatelessWidget {
  const _ProfileRightColumn({required this.patientId, required this.status});

  final String patientId;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileCard(
          title: 'Patient Identification',
          description: 'Your clinic identification number',
          icon: Icons.badge_outlined,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(19),
            decoration: BoxDecoration(
              color: _primarySoft(context),
              border: Border.all(color: _primaryBorder(context)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PATIENT ID',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  patientId,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontSize: 23,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Use this number when communicating with Gonzales Vision '
                  'Clinic about your patient account.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .extension<PatientPortalTextColors>()!
                        .secondary,
                    fontSize: 12,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _ProfileCard(
          title: 'Account Information',
          description: 'Information about your portal account',
          icon: Icons.schedule_outlined,
          child: Column(
            children: [
              const _AccountInformationRow(
                icon: Icons.person_outline,
                label: 'Account Type',
                value: 'Patient',
                first: true,
              ),
              _AccountInformationRow(
                icon: Icons.headset_mic_outlined,
                label: 'Portal Access',
                value: status,
              ),
              const _AccountInformationRow(
                icon: Icons.article_outlined,
                label: 'Patient Record',
                value: 'View-only',
                last: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.child,
  });

  final String title;
  final String description;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.light ? 0.035 : 0.12,
            ),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: Row(
              children: [
                Container(
                  width: 39,
                  height: 39,
                  decoration: BoxDecoration(
                    color: _primarySoft(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: theme.colorScheme.primary, size: 20),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontSize: 16,
                          height: 1.3,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outline),
          Padding(padding: const EdgeInsets.all(20), child: child),
        ],
      ),
    );
  }
}

class _InformationRow extends StatelessWidget {
  const _InformationRow({
    required this.label,
    required this.value,
    this.last = false,
  });

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 550;
        return Container(
          padding: EdgeInsets.only(
            top: stacked ? 12 : 15,
            bottom: last
                ? 0
                : stacked
                ? 12
                : 15,
          ),
          decoration: last
              ? null
              : BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: theme.colorScheme.outline),
                  ),
                ),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      value,
                      softWrap: true,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 175,
                      child: Text(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Text(
                        value,
                        softWrap: true,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 14,
                          height: 1.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _AccountInformationRow extends StatelessWidget {
  const _AccountInformationRow({
    required this.icon,
    required this.label,
    required this.value,
    this.first = false,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;

    return Container(
      padding: EdgeInsets.only(top: first ? 0 : 14, bottom: last ? 0 : 14),
      decoration: last
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outline),
              ),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.light
                  ? const Color(0xFFF8FAFC)
                  : const Color(0xFF162238),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: secondary),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: secondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PatientStatus extends StatelessWidget {
  const _PatientStatus({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final success = theme.brightness == Brightness.light
        ? const Color(0xFF16A34A)
        : const Color(0xFF4ADE80);
    final background = theme.brightness == Brightness.light
        ? const Color(0xFFECFDF3)
        : success.withValues(alpha: 0.12);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: success, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: success,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.light ? 0.035 : 0.12,
            ),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _primarySoft(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.verified_user_outlined,
              color: theme.colorScheme.primary,
              size: 19,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your patient information is protected',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Your profile information is displayed for reference only. '
                  'If you need to update your personal or contact information, '
                  'please contact Gonzales Vision Clinic directly.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondary,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentityError extends StatelessWidget {
  const _IdentityError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('profile-identity-error'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            key: const ValueKey('profile-identity-retry'),
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _PrimaryDot extends StatelessWidget {
  const _PrimaryDot();

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.circle, size: 7, color: Theme.of(context).colorScheme.primary);
}

Color _primarySoft(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
    ? const Color(0xFFEFF6FF)
    : const Color(0xFF122C58);

Color _primaryBorder(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
    ? const Color(0xFFBFDBFE)
    : const Color(0xFF244F91);

DateTime? _parseProfileDate(String value) {
  final normalized = value.trim();
  final datePrefix = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(normalized);
  if (datePrefix != null) {
    final year = int.parse(datePrefix[1]!);
    final month = int.parse(datePrefix[2]!);
    final day = int.parse(datePrefix[3]!);
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }
  return DateTime.tryParse(normalized);
}
