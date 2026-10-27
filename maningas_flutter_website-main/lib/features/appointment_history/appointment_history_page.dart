import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/responsive.dart';
import '../../app/theme.dart';
import '../../core/network/api_failure.dart';
import '../auth/application/patient_auth_controller.dart';
import '../auth/application/patient_auth_scope.dart';
import '../auth/domain/patient_session.dart';
import 'appointment_history_record.dart';
import 'appointment_history_repository.dart';

enum AppointmentHistoryFilter {
  all('All'),
  upcoming('Upcoming'),
  past('Past');

  const AppointmentHistoryFilter(this.label);

  final String label;
}

enum AppointmentHistoryPresentationState {
  ready,
  loading,
  error,
  authenticationRequired,
}

class AppointmentHistoryPage extends StatefulWidget {
  const AppointmentHistoryPage({
    this.appointments,
    this.now,
    this.presentationState,
    super.key,
  });

  final List<AppointmentHistoryRecord>? appointments;
  final DateTime? now;
  final AppointmentHistoryPresentationState? presentationState;

  @override
  State<AppointmentHistoryPage> createState() => _AppointmentHistoryPageState();
}

class _AppointmentHistoryPageState extends State<AppointmentHistoryPage> {
  static const _pageSize = 5;
  AppointmentHistoryFilter _filter = AppointmentHistoryFilter.all;
  int _currentPage = 1;
  PatientAuthController? _controller;
  AppointmentHistoryRepository? _repository;
  List<AppointmentHistoryRecord> _records = const [];
  AppointmentHistoryPresentationState _loadState =
      AppointmentHistoryPresentationState.ready;
  String? _errorMessage;
  String? _requestedSessionKey;
  Timer? _refreshTimer;
  bool _requestInProgress = false;
  int _loadGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = PatientAuthScope.maybeOf(context);
    final repository = PatientAuthScope.appointmentsHistoryOf(context);
    if (controller != _controller) {
      _controller?.removeListener(_handleSessionChange);
      _controller = controller;
      _controller?.addListener(_handleSessionChange);
    }
    if (repository != _repository) {
      _repository = repository;
      _requestedSessionKey = null;
    }
    if (widget.appointments == null && widget.presentationState == null) {
      _loadForCurrentSession();
    }
  }

  @override
  void didUpdateWidget(covariant AppointmentHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.appointments != oldWidget.appointments) {
      _records = widget.appointments ?? const [];
      _currentPage = 1;
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _requestInProgress = false;
    _refreshTimer?.cancel();
    _controller?.removeListener(_handleSessionChange);
    super.dispose();
  }

  void _handleSessionChange() {
    if (widget.appointments == null && widget.presentationState == null) {
      _loadForCurrentSession();
    }
  }

  void _loadForCurrentSession() {
    final repository = _repository;
    if (repository == null) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      _requestedSessionKey = null;
      _loadGeneration++;
      _requestInProgress = false;
      if (_loadState !=
          AppointmentHistoryPresentationState.authenticationRequired) {
        setState(() {
          _records = const [];
          _loadState =
              AppointmentHistoryPresentationState.authenticationRequired;
          _errorMessage = 'Appointment history is not connected to the API.';
          _currentPage = 1;
        });
      }
      return;
    }
    final session = _controller?.currentSession;
    if (session == null) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      _loadGeneration++;
      _requestInProgress = false;
      _requestedSessionKey = null;
      if (_loadState !=
          AppointmentHistoryPresentationState.authenticationRequired) {
        setState(() {
          _loadState =
              AppointmentHistoryPresentationState.authenticationRequired;
          _errorMessage = null;
          _records = const [];
          _currentPage = 1;
        });
      }
      return;
    }
    final key = '${session.patientId}\u0000${session.token}';
    if (_requestedSessionKey == key) return;
    _refreshTimer?.cancel();
    _requestedSessionKey = key;
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshAppointments(),
    );
    _fetchAppointments(repository, session, ++_loadGeneration);
  }

  void _refreshAppointments() {
    if (_requestInProgress ||
        widget.appointments != null ||
        widget.presentationState != null) {
      return;
    }
    final repository = _repository;
    final session = _controller?.currentSession;
    if (repository == null || session == null) return;
    _fetchAppointments(
      repository,
      session,
      ++_loadGeneration,
      silent: true,
    );
  }

  Future<void> _fetchAppointments(
    AppointmentHistoryRepository repository,
    PatientSession session,
    int generation,
    {bool silent = false}
  ) async {
    _requestInProgress = true;
    if (mounted) {
      setState(() {
        if (!silent || _records.isEmpty) {
          _loadState = AppointmentHistoryPresentationState.loading;
        }
        _errorMessage = null;
      });
    }
    try {
      final records = await repository.getAppointments(
        patientId: session.patientId,
        token: session.token,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _records = records;
        _loadState = AppointmentHistoryPresentationState.ready;
        if (!silent) _currentPage = 1;
      });
    } on ApiFailure catch (failure) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadState = failure.statusCode == 401 || failure.statusCode == 403
            ? AppointmentHistoryPresentationState.authenticationRequired
            : AppointmentHistoryPresentationState.error;
        _errorMessage = failure.message;
      });
    } on Exception catch (error, stackTrace) {
      if (!mounted || generation != _loadGeneration) return;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError(
            'Unexpected appointment history failure (${error.runtimeType}).',
          ),
          stack: stackTrace,
          library: 'patient appointment history',
        ),
      );
      setState(() {
        _loadState = AppointmentHistoryPresentationState.error;
        _errorMessage =
            'Your appointment history could not be loaded. Please try again.';
      });
    } finally {
      if (generation == _loadGeneration) _requestInProgress = false;
    }
  }

  void _retry() {
    _requestedSessionKey = null;
    _loadForCurrentSession();
  }

  List<AppointmentHistoryRecord> get _filteredAppointments {
    final now = widget.now ?? DateTime.now();
    final source = widget.appointments ?? _records;
    final filtered =
        source.where((record) {
          final scheduledAt = record.scheduledAt;
          return switch (_filter) {
            AppointmentHistoryFilter.all => true,
            AppointmentHistoryFilter.upcoming =>
              (scheduledAt == null || !scheduledAt.isBefore(now)) &&
                  !_isCancelledStatus(record.status),
            AppointmentHistoryFilter.past =>
              scheduledAt != null && scheduledAt.isBefore(now),
          };
        }).toList()..sort((a, b) {
          final aDate = a.scheduledAt;
          final bDate = b.scheduledAt;
          if (aDate == null) return bDate == null ? 0 : 1;
          if (bDate == null) return -1;
          return bDate.compareTo(aDate);
        });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width <= PatientPortalBreakpoints.mobile;
    final compact = width <= PatientPortalBreakpoints.mobileNavigation;
    final horizontalPadding = width <= 360
        ? 8.0
        : narrow
        ? 12.0
        : compact
        ? 22.0
        : 18.0;
    final appointments = _filteredAppointments;
    final pageCount = (appointments.length / _pageSize).ceil();
    final safePage = pageCount == 0 ? 1 : _currentPage.clamp(1, pageCount);
    final start = (safePage - 1) * _pageSize;
    final pageAppointments = appointments.skip(start).take(_pageSize).toList();

    if (safePage != _currentPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _currentPage = safePage);
      });
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        compact ? 22 : 32,
        horizontalPadding,
        compact ? 28 : 40,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: PatientPortalBreakpoints.contentMaxWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PageHeader(
                compact: compact,
              ),
              const SizedBox(height: 24),
              _HistoryCard(
                selectedFilter: _filter,
                presentationState: widget.presentationState ?? _loadState,
                errorMessage: _errorMessage,
                onRetry: _retry,
                onFilterChanged: (filter) {
                  setState(() {
                    _filter = filter;
                    _currentPage = 1;
                  });
                },
                appointments: pageAppointments,
                hasRecords: appointments.isNotEmpty,
                page: safePage,
                pageSize: _pageSize,
                totalItems: appointments.length,
                onPageChanged: (page) => setState(() => _currentPage = page),
                onOpenDetails: _showDetails,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(AppointmentHistoryRecord appointment) {
    showDialog<void>(
      context: context,
      builder: (context) => _AppointmentDetailsDialog(appointment: appointment),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.compact});

  final bool compact;

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
            Icon(
              Icons.visibility_outlined,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'PATIENT PORTAL',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Appointment History',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontSize: compact ? 28 : 36,
            height: 1.2,
            letterSpacing: -1.2,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Review all of your past visits and upcoming bookings.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: secondary,
            fontSize: compact ? 13 : 14,
            height: 1.6,
          ),
        ),
      ],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.selectedFilter,
    required this.presentationState,
    required this.onFilterChanged,
    required this.appointments,
    required this.hasRecords,
    required this.page,
    required this.pageSize,
    required this.totalItems,
    required this.onPageChanged,
    required this.onOpenDetails,
    required this.errorMessage,
    required this.onRetry,
  });

  final AppointmentHistoryFilter selectedFilter;
  final AppointmentHistoryPresentationState presentationState;
  final ValueChanged<AppointmentHistoryFilter> onFilterChanged;
  final List<AppointmentHistoryRecord> appointments;
  final bool hasRecords;
  final int page;
  final int pageSize;
  final int totalItems;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<AppointmentHistoryRecord> onOpenDetails;
  final String? errorMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.light ? 0.04 : 0.14,
            ),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HistoryCardHeader(secondary: secondary),
          _FilterToolbar(
            selectedFilter: selectedFilter,
            onFilterChanged: onFilterChanged,
          ),
          if (presentationState == AppointmentHistoryPresentationState.ready &&
              hasRecords)
            _PaginationBar(
              page: page,
              pageSize: pageSize,
              totalItems: totalItems,
              onPageChanged: onPageChanged,
            ),
          switch (presentationState) {
            AppointmentHistoryPresentationState.ready =>
              appointments.isEmpty
                  ? const _EmptyState()
                  : _AppointmentList(
                      appointments: appointments,
                      onOpenDetails: onOpenDetails,
                    ),
            AppointmentHistoryPresentationState.loading =>
              _PresentationStateMessage(
                icon: Icons.hourglass_empty,
                title: 'Loading appointment history...',
                detail: 'Fetching your appointment history.',
                loading: true,
              ),
            AppointmentHistoryPresentationState.error =>
              _PresentationStateMessage(
                icon: Icons.error_outline,
                title:
                    'Your appointment history could not be loaded right now.',
                detail: errorMessage ?? 'Your appointment history could not be loaded. Please try again.',
                error: true,
                onRetry: onRetry,
              ),
            AppointmentHistoryPresentationState.authenticationRequired =>
              _PresentationStateMessage(
                icon: Icons.lock_outline,
                title: 'Sign in required',
                detail:
                    errorMessage ??
                    'Sign in again to view your appointment history.',
                error: true,
                onRetry: onRetry,
              ),
          },
        ],
      ),
    );
  }
}

class _HistoryCardHeader extends StatelessWidget {
  const _HistoryCardHeader({required this.secondary});

  final Color secondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _primarySoft(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.calendar_month_outlined,
              color: theme.colorScheme.primary,
              size: 19,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'My appointment records',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your appointment requests and previous visits.',
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
    );
  }
}

class _FilterToolbar extends StatelessWidget {
  const _FilterToolbar({
    required this.selectedFilter,
    required this.onFilterChanged,
  });

  final AppointmentHistoryFilter selectedFilter;
  final ValueChanged<AppointmentHistoryFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 600;

    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 20,
        compact ? 14 : 18,
        compact ? 12 : 20,
        12,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      child: compact
          ? Row(
              children: [
                for (
                  var index = 0;
                  index < AppointmentHistoryFilter.values.length;
                  index++
                ) ...[
                  if (index > 0) const SizedBox(width: 7),
                  Expanded(
                    child: _FilterButton(
                      label: AppointmentHistoryFilter.values[index].label,
                      selected:
                          AppointmentHistoryFilter.values[index] ==
                          selectedFilter,
                      compact: true,
                      onPressed: () => onFilterChanged(
                        AppointmentHistoryFilter.values[index],
                      ),
                    ),
                  ),
                ],
              ],
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AppointmentHistoryFilter.values.map((filter) {
                return _FilterButton(
                  label: filter.label,
                  selected: filter == selectedFilter,
                  compact: false,
                  onPressed: () => onFilterChanged(filter),
                );
              }).toList(),
            ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.label,
    required this.selected,
    required this.compact,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.colorScheme.primary
        : theme.extension<PatientPortalTextColors>()!.secondary;

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        backgroundColor: selected
            ? _primarySoft(context)
            : _surfaceSoft(context),
        side: BorderSide(
          color: selected ? _primaryBorder(context) : theme.colorScheme.outline,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 14,
          vertical: compact ? 7 : 8,
        ),
        minimumSize: Size(0, compact ? 36 : 38),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const StadiumBorder(),
        textStyle: theme.textTheme.labelMedium?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Text(label),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.page,
    required this.pageSize,
    required this.totalItems,
    required this.onPageChanged,
  });

  final int page;
  final int pageSize;
  final int totalItems;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;
    final compact = MediaQuery.sizeOf(context).width <= 800;
    final totalPages = (totalItems / pageSize).ceil();
    final start = (page - 1) * pageSize + 1;
    final end = (page * pageSize).clamp(0, totalItems);

    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 20,
        15,
        compact ? 12 : 20,
        17,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Flex(
        direction: compact ? Axis.vertical : Axis.horizontal,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: compact
            ? CrossAxisAlignment.stretch
            : CrossAxisAlignment.center,
        children: [
          Text(
            'Showing $start-$end of $totalItems',
            textAlign: compact ? TextAlign.center : TextAlign.start,
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(width: compact ? 0 : 12, height: compact ? 10 : 0),
          Wrap(
            alignment: compact ? WrapAlignment.center : WrapAlignment.end,
            spacing: compact ? 5 : 8,
            runSpacing: 6,
            children: [
              _PagerButton(
                label: 'Previous',
                enabled: page > 1,
                compact: compact,
                onPressed: () => onPageChanged(page - 1),
              ),
              for (var number = 1; number <= totalPages; number++)
                _PageNumberButton(
                  number: number,
                  active: number == page,
                  compact: compact,
                  onPressed: () => onPageChanged(number),
                ),
              _PagerButton(
                label: 'Next',
                enabled: page < totalPages,
                compact: compact,
                onPressed: () => onPageChanged(page + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PagerButton extends StatelessWidget {
  const _PagerButton({
    required this.label,
    required this.enabled,
    required this.compact,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: enabled ? onPressed : null,
      style: _pagerStyle(context, compact),
      child: Text(label),
    );
  }
}

class _PageNumberButton extends StatelessWidget {
  const _PageNumberButton({
    required this.number,
    required this.active,
    required this.compact,
    required this.onPressed,
  });

  final int number;
  final bool active;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton(
      onPressed: active ? null : onPressed,
      style: _pagerStyle(context, compact).copyWith(
        minimumSize: WidgetStatePropertyAll(
          Size(compact ? 34 : 38, compact ? 35 : 38),
        ),
        backgroundColor: WidgetStatePropertyAll(
          active ? _primarySoft(context) : _surfaceSoft(context),
        ),
        side: WidgetStatePropertyAll(
          BorderSide(
            color: active ? _primaryBorder(context) : theme.colorScheme.outline,
          ),
        ),
        foregroundColor: WidgetStatePropertyAll(
          active
              ? theme.colorScheme.primary
              : theme.extension<PatientPortalTextColors>()!.secondary,
        ),
      ),
      child: Text('$number'),
    );
  }
}

ButtonStyle _pagerStyle(BuildContext context, bool compact) {
  final theme = Theme.of(context);
  return OutlinedButton.styleFrom(
    foregroundColor: theme.extension<PatientPortalTextColors>()!.secondary,
    backgroundColor: _surfaceSoft(context),
    side: BorderSide(color: theme.colorScheme.outline),
    minimumSize: Size(0, compact ? 35 : 38),
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 9 : 12,
      vertical: compact ? 7 : 8,
    ),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    textStyle: theme.textTheme.labelMedium?.copyWith(
      fontSize: compact ? 11 : 13,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _AppointmentList extends StatelessWidget {
  const _AppointmentList({
    required this.appointments,
    required this.onOpenDetails,
  });

  final List<AppointmentHistoryRecord> appointments;
  final ValueChanged<AppointmentHistoryRecord> onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 800;
    final mobile = MediaQuery.sizeOf(context).width <= 600;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        mobile ? 12 : 20,
        mobile ? 12 : 18,
        mobile ? 12 : 20,
        mobile ? 12 : 20,
      ),
      child: Column(
        children: [
          for (var i = 0; i < appointments.length; i++) ...[
            if (i > 0) SizedBox(height: mobile ? 10 : 12),
            _AppointmentItem(
              appointment: appointments[i],
              compact: compact,
              mobile: mobile,
              onTap: () => onOpenDetails(appointments[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _AppointmentItem extends StatelessWidget {
  const _AppointmentItem({
    required this.appointment,
    required this.compact,
    required this.mobile,
    required this.onTap,
  });

  final AppointmentHistoryRecord appointment;
  final bool compact;
  final bool mobile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;
    final date = appointment.date;

    return Material(
      color: _surfaceSoft(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: mobile ? 11 : 16,
            vertical: mobile ? 13 : 18,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outline),
            borderRadius: BorderRadius.circular(12),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 450;
              final dateBox = _AppointmentDateBox(
                date: date,
                width: mobile
                    ? 46
                    : compact
                    ? 56
                    : 62,
                size: mobile
                    ? 50
                    : compact
                    ? 56
                    : 62,
              );
              final appointmentSummary = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appointment.purpose ?? 'Purpose unavailable',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: mobile ? 14 : 17,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.25,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    [
                      _formatDate(date),
                      _formatTime(appointment.time),
                      appointment.source,
                    ].whereType<String>().join(' · '),
                    maxLines: mobile ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      fontSize: mobile ? 11 : 13,
                      height: 1.5,
                    ),
                  ),
                ],
              );

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        dateBox,
                        const SizedBox(width: 10),
                        Expanded(child: appointmentSummary),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _StatusBadge(
                        status: appointment.status ?? 'Status unavailable',
                      ),
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  dateBox,
                  const SizedBox(width: 16),
                  Expanded(child: appointmentSummary),
                  const SizedBox(width: 12),
                  _StatusBadge(
                    status: appointment.status ?? 'Status unavailable',
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AppointmentDateBox extends StatelessWidget {
  const _AppointmentDateBox({
    required this.date,
    required this.width,
    required this.size,
  });

  final DateTime? date;
  final double width;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      height: size,
      decoration: BoxDecoration(
        color: _primarySoft(context),
        border: Border.all(color: _primaryBorder(context)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            date == null ? '—' : _monthShort(date!.month).toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            date == null ? '—' : '${date!.day}',
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontSize: 22,
              height: 1,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _statusColors(context, status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        softWrap: true,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colors.foreground,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      child: Column(
        children: [
          Icon(
            Icons.event_busy_outlined,
            size: 36,
            color: secondary.withValues(alpha: 0.8),
          ),
          const SizedBox(height: 12),
          Text(
            'No appointment records found',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You do not currently have any appointments matching this filter.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PresentationStateMessage extends StatelessWidget {
  const _PresentationStateMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.error = false,
    this.onRetry,
    this.loading = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool error;
  final VoidCallback? onRetry;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;
    final foreground = error
        ? theme.brightness == Brightness.light
              ? const Color(0xFFDC2626)
              : const Color(0xFFF87171)
        : secondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: Row(
        children: [
          if (loading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, color: foreground),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: error ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(color: secondary),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppointmentDetailsDialog extends StatelessWidget {
  const _AppointmentDetailsDialog({required this.appointment});

  final AppointmentHistoryRecord appointment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final narrow = MediaQuery.sizeOf(context).width <= 800;
    final fields = <(String, String)>[
      ('Appointment ID', appointment.id ?? 'Not available'),
      ('Date', _formatDate(appointment.date)),
      ('Time', _formatTime(appointment.time) ?? 'Not available'),
      ('Patient', appointment.patientName ?? 'Not available'),
      ('Service / purpose', appointment.purpose ?? 'Not available'),
    ];

    return Dialog(
      insetPadding: EdgeInsets.all(narrow ? 10 : 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(narrow ? 16 : 24, 20, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'APPOINTMENT RECORD',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          appointment.purpose ?? 'Purpose unavailable',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_formatDate(appointment.date)} · ${_formatTime(appointment.time) ?? 'Time unavailable'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme
                                .extension<PatientPortalTextColors>()!
                                .secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close appointment details',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.colorScheme.outline),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(narrow ? 14 : 22),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Appointment status',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme
                                  .extension<PatientPortalTextColors>()!
                                  .secondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        _StatusBadge(
                          status: appointment.status ?? 'Status unavailable',
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth <= 460 ? 1 : 2;
                        return _DetailsGrid(fields: fields, columns: columns);
                      },
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                narrow ? 14 : 24,
                0,
                narrow ? 14 : 24,
                narrow ? 14 : 22,
              ),
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close details'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailsGrid extends StatelessWidget {
  const _DetailsGrid({required this.fields, required this.columns});

  final List<(String, String)> fields;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - ((columns - 1) * 12)) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: fields
              .map(
                (field) => SizedBox(
                  width: width,
                  child: _DetailField(label: field.$1, value: field.$2),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceSoft(context),
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.extension<PatientPortalTextColors>()!.secondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 7),
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
      ),
    );
  }
}

class _StatusColors {
  const _StatusColors(this.background, this.foreground, this.border);

  final Color background;
  final Color foreground;
  final Color border;
}

_StatusColors _statusColors(BuildContext context, String status) {
  final theme = Theme.of(context);
  final normalized = status.trim().toLowerCase();
  if (normalized == 'completed' || normalized == 'done') {
    return _StatusColors(
      theme.brightness == Brightness.light
          ? const Color(0xFFECFDF3)
          : const Color(0xFF102C20),
      theme.brightness == Brightness.light
          ? const Color(0xFF16A34A)
          : const Color(0xFF4ADE80),
      theme.brightness == Brightness.light
          ? const Color(0xFFBBF7D0)
          : const Color(0xFF1B5A38),
    );
  }
  if (const {
    'cancelled',
    'canceled',
    'rejected',
    'declined',
  }.contains(normalized)) {
    return _StatusColors(
      theme.brightness == Brightness.light
          ? const Color(0xFFFEF2F2)
          : const Color(0xFF35171B),
      theme.brightness == Brightness.light
          ? const Color(0xFFDC2626)
          : const Color(0xFFF87171),
      theme.brightness == Brightness.light
          ? const Color(0xFFFECACA)
          : const Color(0xFF6B2C34),
    );
  }
  if (const {'in progress', 'in-progress', 'processing'}.contains(normalized)) {
    return _StatusColors(
      theme.brightness == Brightness.light
          ? const Color(0xFFFFFBEB)
          : const Color(0xFF32240D),
      theme.brightness == Brightness.light
          ? const Color(0xFFD97706)
          : const Color(0xFFFBBF24),
      theme.brightness == Brightness.light
          ? const Color(0xFFFCD34D)
          : const Color(0xFF725116),
    );
  }
  return _StatusColors(
    _primarySoft(context),
    theme.colorScheme.primary,
    _primaryBorder(context),
  );
}

bool _isCancelledStatus(String? status) => const {
  'cancelled',
  'canceled',
  'rejected',
  'declined',
}.contains(status?.trim().toLowerCase());

String _formatDate(DateTime? date) => date == null
    ? 'Date unavailable'
    : '${_monthShort(date.month)} ${date.day}, ${date.year}';

String? _formatTime(String? time) {
  if (time == null) return null;
  final parts = time.split(':');
  final hour = int.parse(parts[0]);
  final minute = parts[1];
  final suffix = hour >= 12 ? 'PM' : 'AM';
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  return '$displayHour:$minute $suffix';
}

String _monthShort(int month) => const [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][month - 1];

Color _primarySoft(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
    ? const Color(0xFFEFF6FF)
    : const Color(0xFF122C58);

Color _primaryBorder(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
    ? const Color(0xFFBFDBFE)
    : const Color(0xFF244F91);

Color _surfaceSoft(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
    ? const Color(0xFFF8FAFC)
    : const Color(0xFF162238);
