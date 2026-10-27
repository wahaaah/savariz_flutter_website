import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../appointment_history/appointment_history_record.dart';

class MyAppointmentsSection extends StatefulWidget {
  const MyAppointmentsSection({
    required this.appointments,
    required this.now,
    this.onCancel,
    this.isCancelling = false,
    super.key,
  });

  final List<AppointmentHistoryRecord> appointments;
  final DateTime now;
  final ValueChanged<AppointmentHistoryRecord>? onCancel;
  final bool isCancelling;

  @override
  State<MyAppointmentsSection> createState() => _MyAppointmentsSectionState();
}

class _MyAppointmentsSectionState extends State<MyAppointmentsSection> {
  static const _pageSize = 5;
  int _page = 1;

  List<_GroupedAppointment> get _pageAppointments {
    final upcoming =
        widget.appointments
            .where((appointment) {
              final scheduledAt = appointment.scheduledAt;
              return scheduledAt != null && !scheduledAt.isBefore(widget.now);
            })
            .toList()
          ..sort(_compareBookingRecency);
    final past =
        widget.appointments
            .where((appointment) {
              final scheduledAt = appointment.scheduledAt;
              return scheduledAt != null && scheduledAt.isBefore(widget.now);
            })
            .toList()
          ..sort(_compareBookingRecency);
    final grouped = [
      ...upcoming.map(
        (appointment) => _GroupedAppointment(
          appointment: appointment,
          group: _AppointmentGroup.upcoming,
        ),
      ),
      ...past.map(
        (appointment) => _GroupedAppointment(
          appointment: appointment,
          group: _AppointmentGroup.past,
        ),
      ),
    ];
    final pageCount = (grouped.length / _pageSize).ceil();
    final safePage = pageCount == 0 ? 1 : _page.clamp(1, pageCount);
    if (safePage != _page) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _page = safePage);
      });
    }
    final start = (safePage - 1) * _pageSize;
    return grouped.skip(start).take(_pageSize).toList();
  }

  int _compareBookingRecency(
    AppointmentHistoryRecord a,
    AppointmentHistoryRecord b,
  ) {
    final bookingIdOrder = _numericId(b.id).compareTo(_numericId(a.id));
    if (bookingIdOrder != 0) return bookingIdOrder;
    return (b.scheduledAt ?? DateTime(0)).compareTo(
      a.scheduledAt ?? DateTime(0),
    );
  }

  int _numericId(String? id) {
    final match = RegExp(r'(\d+)$').firstMatch((id ?? '').trim());
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;
    final items = _pageAppointments;
    final total = widget.appointments.length;
    final pageCount = (total / _pageSize).ceil();
    final currentPage = pageCount == 0 ? 1 : _page.clamp(1, pageCount);
    final firstItem = total == 0 ? 0 : (currentPage - 1) * _pageSize + 1;
    final lastItem = (currentPage * _pageSize).clamp(0, total);

    return Card(
      key: const ValueKey('my-appointments-card'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 76),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outline),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.view_list_outlined,
                    color: theme.colorScheme.primary,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'My appointments',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your appointment requests and previous visits',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
              ],
            ),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                "You don't have any appointments yet.",
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: secondary),
              ),
            )
          else ...[
            Padding(
              padding: EdgeInsets.fromLTRB(
                MediaQuery.sizeOf(context).width <= 600 ? 12 : 20,
                0,
                MediaQuery.sizeOf(context).width <= 600 ? 12 : 20,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < items.length; index++) ...[
                    if (index == 0 ||
                        items[index].group != items[index - 1].group)
                      _GroupLabel(group: items[index].group),
                    _AppointmentRow(
                      key: ValueKey(
                        'my-appointment-${items[index].appointment.id}',
                      ),
                      appointment: items[index].appointment,
                      now: widget.now,
                      onCancel: widget.onCancel,
                      isCancelling: widget.isCancelling,
                      showTopBorder:
                          index > 0 &&
                          items[index].group == items[index - 1].group,
                    ),
                  ],
                ],
              ),
            ),
            if (total > _pageSize)
              _Pagination(
                page: currentPage,
                pageCount: pageCount,
                summary: 'Showing $firstItem–$lastItem of $total',
                onPageChanged: (page) => setState(() => _page = page),
              ),
          ],
        ],
      ),
    );
  }
}

enum _AppointmentGroup { upcoming, past }

class _GroupedAppointment {
  const _GroupedAppointment({required this.appointment, required this.group});

  final AppointmentHistoryRecord appointment;
  final _AppointmentGroup group;
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.group});

  final _AppointmentGroup group;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        group == _AppointmentGroup.upcoming
            ? 'Upcoming appointments'
            : 'Past appointments',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context)
              .extension<PatientPortalTextColors>()!
              .secondary,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: .7,
        ),
      ),
    );
  }
}

class _AppointmentRow extends StatelessWidget {
  const _AppointmentRow({
    required this.appointment,
    required this.now,
    required this.showTopBorder,
    required this.onCancel,
    required this.isCancelling,
    super.key,
  });

  final AppointmentHistoryRecord appointment;
  final DateTime now;
  final bool showTopBorder;
  final ValueChanged<AppointmentHistoryRecord>? onCancel;
  final bool isCancelling;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mobile = MediaQuery.sizeOf(context).width <= 700;
    final purpose = appointment.purpose?.trim().isNotEmpty == true
        ? appointment.purpose!.trim()
        : 'Clinic visit';
    final status = appointment.status?.trim().isNotEmpty == true
        ? appointment.status!.trim()
        : 'Unknown';
    final canCancel =
        const {
          'requested',
          'pending',
          'confirmed',
          'approved',
          'scheduled',
          'accepted',
        }.contains(status.toLowerCase()) &&
        (appointment.scheduledAt?.isAfter(now) ?? false);

    return Container(
      padding: EdgeInsets.symmetric(vertical: mobile ? 14 : 17),
      decoration: BoxDecoration(
        border: Border(
          top: showTopBorder
              ? BorderSide(color: theme.colorScheme.outline)
              : BorderSide.none,
          bottom: BorderSide(color: theme.colorScheme.outline),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 550;
          final content = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _DateTile(date: appointment.date),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      purpose,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_longDate(appointment.date)} · ${_time(appointment.time)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme
                            .extension<PatientPortalTextColors>()!
                            .secondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _StatusBadge(
                status: status,
                appointmentId: appointment.id ?? 'unknown',
              ),
              if (canCancel && onCancel != null)
                OutlinedButton(
                  onPressed: isCancelling ? null : () => onCancel!(appointment),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(
                      color: theme.colorScheme.error.withValues(alpha: .35),
                    ),
                  ),
                  child: Text(
                    isCancelling ? 'Cancelling...' : 'Cancel Appointment',
                  ),
                ),
            ],
          );

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                content,
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 61),
                  child: actions,
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: content),
              const SizedBox(width: 12),
              actions,
            ],
          );
        },
      ),
    );
  }

}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.date});

  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF162238)
            : const Color(0xFFF8FAFC),
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(10),
      ),
      child: date == null
          ? const Center(child: Text('—'))
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _monthAbbreviation(date!.month),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.extension<PatientPortalTextColors>()!.secondary,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .4,
                  ),
                ),
                Text(
                  '${date!.day}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 18,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.appointmentId});

  final String status;
  final String appointmentId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalized = status.toLowerCase();
    final color = switch (normalized) {
      'requested' || 'pending' => const Color(0xFFD97706),
      'cancelled' || 'canceled' => const Color(0xFFDC2626),
      'completed' => const Color(0xFF16A34A),
      _ => theme.colorScheme.primary,
    };
    final background = switch (normalized) {
      'requested' || 'pending' => const Color(0xFFFFFBEB),
      'cancelled' || 'canceled' => const Color(0xFFFEF2F2),
      'completed' => const Color(0xFFECFDF3),
      _ => theme.colorScheme.primary.withValues(alpha: .09),
    };
    return Container(
      key: ValueKey('my-appointment-status-$appointmentId'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? color.withValues(alpha: .18)
            : background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  const _Pagination({
    required this.page,
    required this.pageCount,
    required this.summary,
    required this.onPageChanged,
  });

  final int page;
  final int pageCount;
  final String summary;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 18),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 7,
        runSpacing: 8,
        children: [
          OutlinedButton(
            key: const ValueKey('my-appointments-previous'),
            onPressed: page > 1 ? () => onPageChanged(page - 1) : null,
            child: const Text('Previous'),
          ),
          for (var number = 1; number <= pageCount; number++)
            OutlinedButton(
              key: ValueKey('my-appointments-page-$number'),
              onPressed: number == page ? null : () => onPageChanged(number),
              style: number == page
                  ? OutlinedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      side: BorderSide(color: theme.colorScheme.primary),
                    )
                  : null,
              child: Text('$number'),
            ),
          OutlinedButton(
            key: const ValueKey('my-appointments-next'),
            onPressed: page < pageCount ? () => onPageChanged(page + 1) : null,
            child: const Text('Next'),
          ),
          Text(
            summary,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.extension<PatientPortalTextColors>()!.secondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

String _monthAbbreviation(int month) => const [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
][month - 1];

String _longDate(DateTime? date) {
  if (date == null) return 'Date unavailable';
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

String _time(String? value) {
  if (value == null || value.isEmpty) return 'Time unavailable';
  final parts = value.split(':');
  final hour = int.tryParse(parts[0]) ?? 0;
  final minute = parts.length > 1 ? parts[1] : '00';
  return '${hour % 12 == 0 ? 12 : hour % 12}:$minute '
      '${hour >= 12 ? 'PM' : 'AM'}';
}
