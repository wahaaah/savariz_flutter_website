import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/responsive.dart';
import '../../app/theme.dart';
import '../../core/network/api_failure.dart';
import '../auth/application/patient_auth_scope.dart';
import '../auth/domain/patient_session.dart';
import 'notification_repository.dart';
import 'patient_notification.dart';
import 'portal_navigation.dart';
import 'portal_sidebar.dart';

class PortalShell extends StatefulWidget {
  const PortalShell({
    required this.selectedDestination,
    required this.onSelectDestination,
    required this.isDark,
    required this.onToggleTheme,
    required this.child,
    this.onLogout,
    this.logoutEnabled = false,
    super.key,
  });

  final PortalDestination selectedDestination;
  final ValueChanged<PortalDestination> onSelectDestination;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final Widget child;
  final VoidCallback? onLogout;
  final bool logoutEnabled;

  @override
  State<PortalShell> createState() => _PortalShellState();
}

class _PortalShellState extends State<PortalShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _selectFromDrawer(PortalDestination destination) {
    Navigator.of(context).pop();
    widget.onSelectDestination(destination);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile =
            constraints.maxWidth < PatientPortalBreakpoints.mobileNavigation;
        final desktopSidebarWidth =
            constraints.maxWidth <= PatientPortalBreakpoints.tablet
            ? 220.0
            : 250.0;

        return Scaffold(
          key: _scaffoldKey,
          drawer: mobile
              ? Drawer(
                  width: 280,
                  child: SafeArea(
                    child: PortalSidebar(
                      selectedDestination: widget.selectedDestination,
                      onSelectDestination: _selectFromDrawer,
                      onLogout: _handleLogout,
                      width: 280,
                    ),
                  ),
                )
              : null,
          body: Row(
            children: [
              if (!mobile)
                PortalSidebar(
                  selectedDestination: widget.selectedDestination,
                  onSelectDestination: widget.onSelectDestination,
                  onLogout: _handleLogout,
                  width: desktopSidebarWidth,
                ),
              Expanded(
                child: Column(
                  children: [
                    _TopBar(
                      mobile: mobile,
                      narrow:
                          constraints.maxWidth <=
                          PatientPortalBreakpoints.mobile,
                      title: widget.selectedDestination.label,
                      isDark: widget.isDark,
                      onOpenMenu: () => _scaffoldKey.currentState?.openDrawer(),
                      onToggleTheme: widget.onToggleTheme,
                      notificationRepository: PatientAuthScope.notificationsOf(
                        context,
                      ),
                      session: PatientAuthScope.maybeOf(context)
                          ?.currentSession,
                    ),
                    Expanded(child: widget.child),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _handleLogout() {
    if (!widget.logoutEnabled || widget.onLogout == null) {
      _showLogoutNotice();
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.logout),
        title: const Text('Log out?'),
        content: const Text(
          'Your session and any remembered login on this browser will be cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onLogout!();
            },
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }

  void _showLogoutNotice() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.info_outline),
        title: const Text('Presentation-only action'),
        content: const Text(
          'This development screen does not sign out or change account data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatefulWidget {
  const _TopBar({
    required this.mobile,
    required this.narrow,
    required this.title,
    required this.isDark,
    required this.onOpenMenu,
    required this.onToggleTheme,
    required this.notificationRepository,
    required this.session,
  });

  final bool mobile;
  final bool narrow;
  final String title;
  final bool isDark;
  final VoidCallback onOpenMenu;
  final VoidCallback onToggleTheme;
  final NotificationRepository? notificationRepository;
  final PatientSession? session;

  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> {
  final _notifications = <PatientNotification>[];
  final _bellKey = GlobalKey();
  final _notificationTapRegionGroup = Object();
  OverlayEntry? _notificationDropdown;
  Timer? _refreshTimer;
  bool _isLoading = false;
  bool _isMarkingAllRead = false;
  int? _markingNotificationId;
  int? _apiUnreadCount;
  String? _errorMessage;
  bool _hasLoadedApiData = false;
  bool _authenticationFailed = false;
  int _requestGeneration = 0;
  int _mutationGeneration = 0;

  bool get _apiMode =>
      widget.notificationRepository != null && widget.session != null;

  int get _unreadCount =>
      _apiUnreadCount ??
      _notifications.where((notification) => !notification.isRead).length;

  @override
  void initState() {
    super.initState();
    _startApiRefresh();
  }

  @override
  void didUpdateWidget(covariant _TopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPatientId = oldWidget.session?.patientId;
    final newPatientId = widget.session?.patientId;
    final oldToken = oldWidget.session?.token;
    final newToken = widget.session?.token;
    if (oldPatientId != newPatientId ||
        oldToken != newToken ||
        oldWidget.notificationRepository != widget.notificationRepository) {
      _refreshTimer?.cancel();
      _requestGeneration++;
      _isLoading = false;
      _notifications.clear();
      _apiUnreadCount = null;
      _errorMessage = null;
      _hasLoadedApiData = false;
      _authenticationFailed = false;
      _startApiRefresh();
      _refreshDropdown();
    }
  }

  void _startApiRefresh() {
    if (!_apiMode || _authenticationFailed) return;
    _loadApiNotifications();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _loadApiNotifications(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _notificationDropdown?.remove();
    _notificationDropdown = null;
    super.dispose();
  }

  void _toggleDropdown() {
    if (_notificationDropdown != null) {
      _removeDropdown();
      return;
    }
    _notificationDropdown = OverlayEntry(builder: _buildDropdownOverlay);
    Overlay.of(context).insert(_notificationDropdown!);
    setState(() {});
    if (_apiMode && !_authenticationFailed) _loadApiNotifications();
  }

  void _removeDropdown() {
    _notificationDropdown?.remove();
    _notificationDropdown = null;
    if (mounted) setState(() {});
  }

  void _refreshDropdown() {
    if (mounted) setState(() {});
    _notificationDropdown?.markNeedsBuild();
  }

  Future<void> _loadApiNotifications() async {
    final repository = widget.notificationRepository;
    final session = widget.session;
    if (!_apiMode ||
        _authenticationFailed ||
        repository == null ||
        session == null ||
        _isLoading) {
      return;
    }
    final generation = _requestGeneration;
    final mutationGeneration = _mutationGeneration;
    _isLoading = true;
    _errorMessage = null;
    if (!_hasLoadedApiData) _refreshDropdown();
    try {
      final notifications = await repository.getNotifications(
        patientId: session.patientId,
        token: session.token,
      );
      final unreadCount = await repository.getUnreadCount(
        patientId: session.patientId,
        token: session.token,
      );
      if (!mounted ||
          generation != _requestGeneration ||
          mutationGeneration != _mutationGeneration ||
          widget.session?.token != session.token) {
        return;
      }
      final listUnreadCount = notifications
          .where((notification) => !notification.isRead)
          .length;
      setState(() {
        _notifications
          ..clear()
          ..addAll(notifications);
        _apiUnreadCount = unreadCount == listUnreadCount
            ? unreadCount
            : listUnreadCount;
        _hasLoadedApiData = true;
        _errorMessage = null;
      });
    } on ApiFailure catch (failure) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _recordNotificationFailure(failure);
      });
    } finally {
      if (generation == _requestGeneration) {
        _isLoading = false;
        _notificationDropdown?.markNeedsBuild();
      }
    }
  }

  void _recordNotificationFailure(ApiFailure failure) {
    _errorMessage = failure.message;
    if (failure.statusCode == 401) {
      _authenticationFailed = true;
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  Future<void> _markNotificationRead(PatientNotification notification) async {
    if (notification.isRead) return;
    final repository = widget.notificationRepository;
    final session = widget.session;
    if (!_apiMode || repository == null || session == null) return;
    _markingNotificationId = notification.id;
    _errorMessage = null;
    _refreshDropdown();
    try {
      await repository.markAsRead(
        notificationId: notification.id,
        token: session.token,
      );
      if (!mounted || widget.session?.token != session.token) return;
      final index = _notifications.indexWhere(
        (item) => item.id == notification.id,
      );
      if (index >= 0 && !_notifications[index].isRead) {
        _notifications[index] = _notifications[index].copyWith(isRead: true);
        _mutationGeneration++;
        _apiUnreadCount = ((_apiUnreadCount ?? _unreadCount) - 1)
            .clamp(0, 1 << 31)
            .toInt();
      }
    } on ApiFailure catch (failure) {
      if (mounted) _recordNotificationFailure(failure);
    } finally {
      _markingNotificationId = null;
      _refreshDropdown();
    }
  }

  Future<void> _markAllNotificationsRead() async {
    final repository = widget.notificationRepository;
    final session = widget.session;
    if (!_apiMode || repository == null || session == null) return;
    _isMarkingAllRead = true;
    _errorMessage = null;
    _refreshDropdown();
    try {
      await repository.markAllAsRead(
        patientId: session.patientId,
        token: session.token,
      );
      if (!mounted || widget.session?.token != session.token) return;
      for (var index = 0; index < _notifications.length; index++) {
        _notifications[index] = _notifications[index].copyWith(isRead: true);
      }
      _mutationGeneration++;
      _apiUnreadCount = 0;
    } on ApiFailure catch (failure) {
      if (mounted) _recordNotificationFailure(failure);
    } finally {
      _isMarkingAllRead = false;
      _refreshDropdown();
    }
  }

  String _notificationTimestamp(
    BuildContext context,
    PatientNotification notification,
  ) {
    final timestamp = notification.createdAt;
    if (timestamp == null) return '';
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatMediumDate(timestamp.toLocal());
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(timestamp.toLocal()),
    );
    return '$date · $time';
  }

  Widget _buildDropdownOverlay(BuildContext overlayContext) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;
    final viewport = MediaQuery.sizeOf(overlayContext);
    final dropdownWidth = (viewport.width - 24).clamp(0.0, 360.0);
    final dropdownHeight = (viewport.height - (widget.narrow ? 82 : 90)).clamp(
      220.0,
      480.0,
    );

    return TapRegion(
      groupId: _notificationTapRegionGroup,
      onTapOutside: (_) => _removeDropdown(),
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: EdgeInsets.only(top: widget.narrow ? 64 : 72, right: 12),
          child: SizedBox(
            width: dropdownWidth,
            height: dropdownHeight,
            child: Material(
              key: const ValueKey('notification-dropdown'),
              color: theme.colorScheme.surface,
              elevation: 12,
              shadowColor: Colors.black.withValues(alpha: 0.18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: theme.colorScheme.outline),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 300;
                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 8 : 16,
                          14,
                          compact ? 8 : 12,
                          12,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                'Notifications',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    (compact
                                            ? theme.textTheme.titleSmall
                                            : theme.textTheme.titleMedium)
                                        ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            SizedBox(width: compact ? 4 : 8),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 6 : 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                '$_unreadCount unread',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            SizedBox(width: compact ? 2 : 8),
                            Expanded(
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(0, 28),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: compact ? 0 : 2,
                                  ),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  textStyle: theme.textTheme.labelSmall,
                                ),
                                onPressed:
                                    _unreadCount == 0 || _isMarkingAllRead
                                    ? null
                                    : _markAllNotificationsRead,
                                child: const Text(
                                  'Mark all as read',
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  Divider(height: 1, color: theme.colorScheme.outline),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 7, 14, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'PATIENT NOTIFICATIONS',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: secondary,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: _notificationList(theme)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _notificationList(ThemeData theme) {
    if (_isLoading && !_hasLoadedApiData) {
      return const Center(
        child: CircularProgressIndicator(
          key: ValueKey('notifications-loading'),
        ),
      );
    }
    if (_errorMessage != null && !_hasLoadedApiData) {
      return _NotificationMessage(
        message: _errorMessage!,
        actionLabel: _authenticationFailed ? null : 'Retry',
        onPressed: _authenticationFailed ? null : _loadApiNotifications,
      );
    }
    if (_notifications.isEmpty) {
      return Column(
        children: [
          if (_errorMessage != null) _notificationErrorBanner(),
          Expanded(
            child: Center(
              child: Text(
                'No notifications to show.',
                key: const ValueKey('notifications-empty'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.extension<PatientPortalTextColors>()!.secondary,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        if (_errorMessage != null) _notificationErrorBanner(),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: _notifications.length,
            separatorBuilder: (context, index) =>
                Divider(height: 1, color: theme.colorScheme.outline),
            itemBuilder: (context, index) {
              final notification = _notifications[index];
              return _NotificationItem(
                notification: notification,
                timestamp: _notificationTimestamp(context, notification),
                isBusy: _markingNotificationId == notification.id,
                onTap:
                    notification.isRead ||
                        _markingNotificationId == notification.id
                    ? null
                    : () => _markNotificationRead(notification),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _notificationErrorBanner() {
    return _NotificationMessage(
      message: _errorMessage!,
      actionLabel: _authenticationFailed ? null : 'Retry',
      onPressed: _authenticationFailed ? null : _loadApiNotifications,
      compact: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;
    final patientName = widget.session?.name.trim();
    final patientInitial = patientName == null || patientName.isEmpty
        ? 'P'
        : String.fromCharCode(patientName.runes.first).toUpperCase();

    return Container(
      height: widget.narrow ? 64 : 72,
      padding: EdgeInsets.symmetric(horizontal: widget.mobile ? 12 : 28),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Row(
        children: [
          if (widget.mobile)
            IconButton(
              tooltip: 'Open navigation menu',
              onPressed: widget.onOpenMenu,
              icon: const Icon(Icons.menu),
            ),
          if (!widget.mobile)
            Text(
              'Patient Portal',
              style: theme.textTheme.bodyMedium?.copyWith(color: secondary),
            ),
          if (!widget.mobile)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Icon(Icons.chevron_right, size: 18, color: secondary),
            ),
          Expanded(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _TopBarButton(
            tooltip: widget.isDark
                ? 'Switch to light theme'
                : 'Switch to dark theme',
            onPressed: widget.onToggleTheme,
            icon: widget.isDark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
          ),
          const SizedBox(width: 10),
          _TopBarButton(
            key: _bellKey,
            tooltip: 'Notifications',
            onPressed: _toggleDropdown,
            icon: Icons.notifications_none,
            badgeCount: _unreadCount,
            tapRegionGroupId: _notificationTapRegionGroup,
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: widget.narrow ? 17 : 18,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            foregroundColor: theme.colorScheme.primary,
            child: Text(patientInitial),
          ),
          if (!widget.mobile) ...[
            const SizedBox(width: 10),
            _AccountIdentity(name: patientName),
          ],
        ],
      ),
    );
  }
}

class _TopBarButton extends StatelessWidget {
  const _TopBarButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.badgeCount = 0,
    this.tapRegionGroupId,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;
  final int badgeCount;
  final Object? tapRegionGroupId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 38,
      height: 38,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: TapRegion(
              groupId: tapRegionGroupId,
              child: IconButton(
                tooltip: tooltip,
                onPressed: onPressed,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 38,
                  height: 38,
                ),
                style: IconButton.styleFrom(
                  foregroundColor: theme
                      .extension<PatientPortalTextColors>()!
                      .secondary,
                  side: BorderSide(color: theme.colorScheme.outline),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: Icon(icon, size: 18),
              ),
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              right: -5,
              top: -5,
              child: _UnreadCountBadge(count: badgeCount),
            ),
        ],
      ),
    );
  }
}

class _UnreadCountBadge extends StatelessWidget {
  const _UnreadCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFDC2626),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _NotificationItem extends StatelessWidget {
  const _NotificationItem({
    required this.notification,
    required this.timestamp,
    required this.isBusy,
    required this.onTap,
  });

  final PatientNotification notification;
  final String timestamp;
  final bool isBusy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;
    final unread = !notification.isRead;

    return InkWell(
      onTap: onTap,
      canRequestFocus: onTap != null,
      child: Container(
        color: unread
            ? theme.colorScheme.primary.withValues(alpha: 0.035)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.notifications_none,
                size: 18,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (unread)
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      if (isBusy) ...[
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    timestamp,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationMessage extends StatelessWidget {
  const _NotificationMessage({
    required this.message,
    required this.actionLabel,
    required this.onPressed,
    this.compact = false,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 18,
        vertical: compact ? 8 : 20,
      ),
      child: compact
          ? Row(
              children: [
                Expanded(
                  child: Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                    ),
                  ),
                ),
                if (actionLabel != null)
                  TextButton(onPressed: onPressed, child: Text(actionLabel!)),
              ],
            )
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  if (actionLabel != null)
                    TextButton(onPressed: onPressed, child: Text(actionLabel!)),
                ],
              ),
            ),
    );
  }
}

class _AccountIdentity extends StatelessWidget {
  const _AccountIdentity({required this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context)
        .extension<PatientPortalTextColors>()!
        .secondary;
    final displayName = name?.trim();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          displayName == null || displayName.isEmpty ? 'Patient' : displayName,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          'Patient account',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: secondary),
        ),
      ],
    );
  }
}
