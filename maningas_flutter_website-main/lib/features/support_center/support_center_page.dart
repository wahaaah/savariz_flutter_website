import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/responsive.dart';
import '../../app/theme.dart';
import '../../core/network/api_failure.dart';
import '../auth/application/patient_auth_controller.dart';
import '../auth/application/patient_auth_scope.dart';
import '../auth/domain/patient_session.dart';
import 'support_center_repository.dart';
import 'support_ticket.dart';

class SupportCenterPage extends StatefulWidget {
  const SupportCenterPage({this.tickets, super.key});

  final List<SupportTicket>? tickets;

  @override
  State<SupportCenterPage> createState() => _SupportCenterPageState();
}

class _SupportCenterPageState extends State<SupportCenterPage> {
  final List<SupportTicket> _tickets = [];
  String? _selectedTicketId;
  final _messageController = TextEditingController();
  PatientAuthController? _controller;
  SupportCenterRepository? _repository;
  Timer? _statusTimer;
  Timer? _ticketRefreshTimer;
  String? _requestedSessionKey;
  String? _loadError;
  int _loadGeneration = 0;
  bool _isLoading = false;
  bool _isLoadingMessages = false;
  bool _isSending = false;
  bool _isCancelling = false;
  bool _isRefreshingStatus = false;
  bool _isRefreshingInbox = false;

  @override
  void initState() {
    super.initState();
    _tickets.addAll(widget.tickets ?? const []);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = PatientAuthScope.maybeOf(context);
    final repository = PatientAuthScope.supportCenterOf(context);
    if (controller != _controller) {
      _controller?.removeListener(_handleSessionChange);
      _controller = controller;
      _controller?.addListener(_handleSessionChange);
    }
    if (repository != _repository) {
      _repository = repository;
      _requestedSessionKey = null;
    }
    _loadForCurrentSession();
  }

  @override
  void dispose() {
    _loadGeneration++;
    _statusTimer?.cancel();
    _ticketRefreshTimer?.cancel();
    _controller?.removeListener(_handleSessionChange);
    _messageController.dispose();
    super.dispose();
  }

  SupportTicket? get _selectedTicket {
    for (final ticket in _tickets) {
      if (ticket.id == _selectedTicketId) return ticket;
    }
    return null;
  }

  bool get _mobile => MediaQuery.sizeOf(context).width <= 640;

  PatientSession? get _session => _controller?.currentSession;

  void _handleSessionChange() {
    _requestedSessionKey = null;
    _loadForCurrentSession();
  }

  void _loadForCurrentSession() {
    final repository = _repository;
    final session = _session;
    if (repository == null || session == null) {
      _statusTimer?.cancel();
      _ticketRefreshTimer?.cancel();
      _requestedSessionKey = null;
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = repository == null
              ? 'Support services are not connected.'
              : 'Please sign in again to use Support Center.';
          _tickets.clear();
          _selectedTicketId = null;
        });
      }
      return;
    }
    final key = '${session.patientId}\u0000${session.token}';
    if (_requestedSessionKey == key) return;
    _requestedSessionKey = key;
    _startTicketRefresh();
    unawaited(_loadTickets());
  }

  void _startTicketRefresh() {
    _ticketRefreshTimer?.cancel();
    if (_selectedTicketId != null || _session == null) return;
    _ticketRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_refreshTicketInbox()),
    );
  }

  Future<void> _refreshTicketInbox() async {
    if (_isRefreshingInbox || _isLoading || _selectedTicketId != null) return;
    final repository = _repository;
    final session = _session;
    if (repository == null || session == null) return;
    _isRefreshingInbox = true;
    try {
      final tickets = await repository.getMyTickets(
        patientId: session.patientId,
        token: session.token,
      );
      final currentSession = _session;
      if (!mounted ||
          currentSession?.patientId != session.patientId ||
          currentSession?.token != session.token) {
        return;
      }
      setState(() {
        _tickets
          ..clear()
          ..addAll(tickets);
        _loadError = null;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _loadError = failure.message);
    } on FormatException catch (error, stackTrace) {
      if (!mounted) return;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'patient support center',
        ),
      );
      setState(
        () => _loadError = 'The clinic service returned invalid support tickets.',
      );
    } finally {
      _isRefreshingInbox = false;
    }
  }

  Future<void> _loadTickets() async {
    final repository = _repository;
    final session = _session;
    if (repository == null || session == null) return;
    final generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final tickets = await repository.getMyTickets(
        patientId: session.patientId,
        token: session.token,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _tickets
          ..clear()
          ..addAll(tickets);
        _isLoading = false;
        if (_selectedTicketId != null &&
            !_tickets.any((ticket) => ticket.id == _selectedTicketId)) {
          _selectedTicketId = null;
          _statusTimer?.cancel();
        }
      });
      final selected = _selectedTicket;
      if (selected != null) {
        await _loadMessages(selected, preserveError: true);
      }
    } on ApiFailure catch (failure) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _isLoading = false;
        _loadError = failure.message;
      });
    } on FormatException catch (error, stackTrace) {
      if (!mounted || generation != _loadGeneration) return;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'patient support center',
        ),
      );
      setState(() {
        _isLoading = false;
        _loadError = 'The clinic service returned invalid support tickets.';
      });
    }
  }

  Future<void> _refreshSelectedTicket() async {
    if (_isRefreshingStatus || _selectedTicketId == null) return;
    _isRefreshingStatus = true;
    try {
      final selectedId = _selectedTicketId;
      final session = _session;
      final repository = _repository;
      if (selectedId == null || session == null || repository == null) return;
      final latestTickets = await repository.getMyTickets(
        patientId: session.patientId,
        token: session.token,
      );
      if (!mounted || selectedId != _selectedTicketId) return;
      final previous = _selectedTicket;
      SupportTicket? latest;
      for (final ticket in latestTickets) {
        if (ticket.id == selectedId) {
          latest = ticket;
          break;
        }
      }
      setState(() {
        _tickets
          ..clear()
          ..addAll(latestTickets);
        if (latest == null) _selectedTicketId = null;
      });
      if (latest == null) {
        _statusTimer?.cancel();
        return;
      }
      if (previous?.status != latest.status ||
          previous?.updatedAt != latest.updatedAt) {
        await _loadMessages(latest, preserveError: true);
      }
      if (['resolved', 'closed'].contains(latest.status.toLowerCase())) {
        _statusTimer?.cancel();
      }
    } on ApiFailure catch (failure) {
      debugPrint('Unable to refresh support ticket status: ${failure.message}');
    } on FormatException catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'patient support center',
        ),
      );
      debugPrint('The clinic service returned invalid support ticket data.');
    } finally {
      _isRefreshingStatus = false;
    }
  }

  void _selectTicket(SupportTicket ticket) {
    _ticketRefreshTimer?.cancel();
    setState(() => _selectedTicketId = ticket.id);
    _messageController.clear();
    _statusTimer?.cancel();
    unawaited(_loadMessages(ticket));
    _statusTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_refreshSelectedTicket()),
    );
  }

  Future<void> _loadMessages(
    SupportTicket ticket, {
    bool preserveError = false,
  }) async {
    final repository = _repository;
    final session = _session;
    if (repository == null || session == null) return;
    setState(() {
      _isLoadingMessages = true;
      if (!preserveError) _loadError = null;
    });
    try {
      final messages = await repository.getMessages(
        patientId: session.patientId,
        token: session.token,
        ticketId: ticket.id,
      );
      if (!mounted || _selectedTicketId != ticket.id) return;
      setState(() {
        final index = _tickets.indexWhere((item) => item.id == ticket.id);
        if (index >= 0) {
          _tickets[index] = _tickets[index].withMessages(messages);
        }
        _isLoadingMessages = false;
      });
      try {
        await repository.markMessagesRead(
          token: session.token,
          ticketId: ticket.id,
        );
      } on ApiFailure catch (failure) {
        debugPrint('Support read receipt unavailable: ${failure.message}');
      }
    } on ApiFailure catch (failure) {
      if (!mounted || _selectedTicketId != ticket.id) return;
      setState(() {
        _isLoadingMessages = false;
        _loadError = failure.message;
      });
    } on FormatException catch (error, stackTrace) {
      if (!mounted || _selectedTicketId != ticket.id) return;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'patient support center',
        ),
      );
      setState(() {
        _isLoadingMessages = false;
        _loadError = 'The clinic service returned invalid support messages.';
      });
    }
  }

  Future<void> _showNewTicketDialog() async {
    final draft = await showDialog<_NewTicketDraft>(
      context: context,
      builder: (context) => const _NewTicketDialog(),
    );
    if (draft == null || !mounted) return;
    final session = _session;
    final repository = _repository;
    if (session == null || repository == null) {
      _showNotice('Please sign in again before creating a support ticket.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final created = await repository.createTicket(
        patientId: session.patientId,
        token: session.token,
        category: draft.category,
        subject: draft.subject,
        description: draft.description,
        priority: draft.priority,
      );
      await _loadTickets();
      if (created != null && mounted) {
        final existing = _tickets.where((ticket) => ticket.id == created.id);
        _selectTicket(existing.isEmpty ? created : existing.first);
      }
      if (mounted) {
        _showNotice(
          created == null
              ? 'Ticket submitted. Select it from your ticket list.'
              : 'Your support ticket was submitted.',
        );
      }
    } on ApiFailure catch (failure) {
      if (mounted) {
        _showNotice('Unable to submit support ticket: ${failure.message}');
      }
    } on FormatException catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'patient support center',
        ),
      );
      if (mounted) {
        _showNotice('The clinic service returned invalid ticket data.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cancelTicket(SupportTicket ticket) async {
    if (ticket.status.toLowerCase() != 'open') {
      _showNotice('Only open support tickets can be cancelled.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_outlined),
        title: const Text('Cancel Support Ticket?'),
        content: Text(
          'Are you sure you want to cancel "${ticket.subject}"? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Ticket'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel Ticket'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final session = _session;
    final repository = _repository;
    if (session == null || repository == null) return;
    setState(() => _isCancelling = true);
    try {
      await repository.cancelTicket(token: session.token, ticketId: ticket.id);
      if (_selectedTicketId == ticket.id) {
        _selectedTicketId = null;
        _statusTimer?.cancel();
        _startTicketRefresh();
      }
      await _loadTickets();
      if (mounted) _showNotice('Support ticket cancelled.');
    } on ApiFailure catch (failure) {
      if (mounted) {
        _showNotice('Unable to cancel support ticket: ${failure.message}');
      }
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  Future<void> _sendMessage() async {
    final ticket = _selectedTicket;
    final session = _session;
    final repository = _repository;
    final message = _messageController.text.trim();
    if (ticket == null ||
        session == null ||
        repository == null ||
        message.isEmpty) {
      return;
    }

    if (!_canSendMessage(ticket)) {
      _showNotice('You can reply after the clinic accepts your ticket.');
      return;
    }
    setState(() => _isSending = true);
    try {
      await repository.sendMessage(
        token: session.token,
        ticketId: ticket.id,
        message: message,
      );
      if (_selectedTicketId == ticket.id) {
        _messageController.clear();
        await _loadMessages(ticket, preserveError: true);
      }
    } on ApiFailure catch (failure) {
      if (mounted) _showNotice('Unable to send message: ${failure.message}');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _backToTickets() {
    _statusTimer?.cancel();
    setState(() => _selectedTicketId = null);
    _startTicketRefresh();
  }

  void _showNotice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width <= PatientPortalBreakpoints.mobile;
    final pagePadding = width <= PatientPortalBreakpoints.mobileNavigation
        ? (compact ? 17.0 : 22.0)
        : width <= PatientPortalBreakpoints.tablet
        ? 25.0
        : 32.0;
    final mobile = _mobile;
    final chatOpen = mobile && _selectedTicket != null;
    final cardHeight = mobile
        ? (MediaQuery.sizeOf(context).height * 0.68).clamp(400.0, 580.0)
        : 620.0;

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
              _PageHeader(onNewTicket: _showNewTicketDialog),
              const SizedBox(height: 18),
              const _PrivacyNotice(),
              const SizedBox(height: 20),
              if (_loadError != null || _isLoading)
                _SupportStatusNotice(
                  message: _loadError ?? 'Loading your support tickets...',
                  isError: _loadError != null,
                  onRetry: _loadError == null ? null : _loadTickets,
                ),
              if (_loadError != null || _isLoading) const SizedBox(height: 14),
              if (mobile)
                SizedBox(
                  height: cardHeight,
                  child: chatOpen
                      ? _ConversationPanel(
                          ticket: _selectedTicket,
                          mobile: true,
                          messageController: _messageController,
                          isLoading: _isLoadingMessages,
                          isSending: _isSending,
                          onBack: _backToTickets,
                          onSend: _sendMessage,
                        )
                      : _InboxPanel(
                          tickets: _tickets,
                          selectedTicketId: _selectedTicketId,
                          mobile: true,
                          onSelect: _selectTicket,
                          isLoading: _isLoading,
                          isCancelling: _isCancelling,
                          onRefresh: _loadTickets,
                          onCancel: _cancelTicket,
                        ),
                )
              else
                SizedBox(
                  height: cardHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: width <= PatientPortalBreakpoints.tablet
                            ? 280
                            : 320,
                        child: _InboxPanel(
                          tickets: _tickets,
                          selectedTicketId: _selectedTicketId,
                          mobile: false,
                          onSelect: _selectTicket,
                          isLoading: _isLoading,
                          isCancelling: _isCancelling,
                          onRefresh: _loadTickets,
                          onCancel: _cancelTicket,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: _ConversationPanel(
                          ticket: _selectedTicket,
                          mobile: false,
                          messageController: _messageController,
                          isLoading: _isLoadingMessages,
                          isSending: _isSending,
                          onBack: () {},
                          onSend: _sendMessage,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.onNewTicket});

  final VoidCallback onNewTicket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Support Center',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Manage your support requests and communicate with our clinic team.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: secondary,
                  height: 1.55,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: onNewTicket,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New Ticket'),
        ),
      ],
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
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'For your privacy, do not share passwords or sensitive payment '
        'information in support messages.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: secondary,
          height: 1.55,
        ),
      ),
    );
  }
}

class _SupportStatusNotice extends StatelessWidget {
  const _SupportStatusNotice({
    required this.message,
    required this.isError,
    required this.onRetry,
  });

  final String message;
  final bool isError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          if (!isError)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _InboxPanel extends StatelessWidget {
  const _InboxPanel({
    required this.tickets,
    required this.selectedTicketId,
    required this.mobile,
    required this.onSelect,
    required this.isLoading,
    required this.isCancelling,
    required this.onRefresh,
    required this.onCancel,
  });

  final List<SupportTicket> tickets;
  final String? selectedTicketId;
  final bool mobile;
  final ValueChanged<SupportTicket> onSelect;
  final bool isLoading;
  final bool isCancelling;
  final VoidCallback onRefresh;
  final ValueChanged<SupportTicket> onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'My Support Tickets',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Track your requests and view their current status.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: isLoading ? null : onRefresh,
                  child: const Text('Refresh'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: isLoading && tickets.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : tickets.isEmpty
                ? const _EmptyInbox()
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: tickets.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 9),
                    itemBuilder: (context, index) {
                      final ticket = tickets[index];
                      return _TicketListItem(
                        ticket: ticket,
                        selected: ticket.id == selectedTicketId,
                        mobile: mobile,
                        onSelect: () => onSelect(ticket),
                        isCancelling: isCancelling,
                        onCancel: () => onCancel(ticket),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _TicketListItem extends StatelessWidget {
  const _TicketListItem({
    required this.ticket,
    required this.selected,
    required this.mobile,
    required this.isCancelling,
    required this.onSelect,
    required this.onCancel,
  });

  final SupportTicket ticket;
  final bool selected;
  final bool mobile;
  final bool isCancelling;
  final VoidCallback onSelect;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOpen = ticket.status.toLowerCase() == 'open';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onSelect,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.start,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: mobile ? 260 : 190,
                        ),
                        child: Text(
                          ticket.subject.isEmpty
                              ? 'Ticket #${ticket.id}'
                              : ticket.subject,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _StatusBadge(status: ticket.status),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      _TicketMeta(text: '#${ticket.id}'),
                      _TicketMeta(text: ticket.category),
                      _TicketMeta(
                        text: _formatDateTime(context, ticket.updatedAt),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (isOpen)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: isCancelling ? null : onCancel,
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
              child: const Text('Cancel Ticket'),
            ),
          ),
      ],
    );
  }
}

class _TicketMeta extends StatelessWidget {
  const _TicketMeta({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context)
        .extension<PatientPortalTextColors>()!
        .secondary;
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: secondary, fontSize: 11),
    );
  }
}

class _ConversationPanel extends StatelessWidget {
  const _ConversationPanel({
    required this.ticket,
    required this.mobile,
    required this.messageController,
    required this.isLoading,
    required this.isSending,
    required this.onBack,
    required this.onSend,
  });

  final SupportTicket? ticket;
  final bool mobile;
  final TextEditingController messageController;
  final bool isLoading;
  final bool isSending;
  final VoidCallback onBack;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;
    final canSend = ticket != null && _canSendMessage(ticket!) && !isSending;
    final readOnly = ticket != null && _isReadOnly(ticket!.status);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 76),
            padding: EdgeInsets.symmetric(
              horizontal: mobile ? 12 : 20,
              vertical: 14,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outline),
              ),
            ),
            child: Row(
              children: [
                if (mobile) ...[
                  OutlinedButton(
                    onPressed: onBack,
                    child: const Text('← Back to Tickets'),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        ticket == null
                            ? 'Support Chat'
                            : '${ticket!.subject} · Ticket #${ticket!.id}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _conversationSubtitle(ticket),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : ticket == null
                ? const _EmptyConversation()
                : ticket!.messages.isEmpty
                ? _NoMessages(canSend: canSend, status: ticket!.status)
                : ListView.builder(
                    padding: const EdgeInsets.all(18),
                    itemCount: ticket!.messages.length,
                    itemBuilder: (context, index) =>
                        _MessageBubble(message: ticket!.messages[index]),
                  ),
          ),
          if (ticket != null && readOnly)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: theme.scaffoldBackgroundColor,
              child: Text(
                'This conversation is read-only.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: secondary),
              ),
            ),
          if (ticket != null && !canSend && !readOnly)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: theme.scaffoldBackgroundColor,
              child: Text(
                ticket!.status.toLowerCase() == 'open'
                    ? 'Waiting for Super Admin to accept your ticket.'
                    : 'Messaging is currently unavailable.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: secondary),
              ),
            ),
          _MessageComposer(
            controller: messageController,
            enabled: canSend,
            isSending: isSending,
            onSend: onSend,
          ),
        ],
      ),
    );
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.enabled,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool isSending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              maxLength: 2000,
              decoration: const InputDecoration(
                hintText: 'Type your message...',
                labelText: 'Type your support message',
                counterText: '',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              onSubmitted: enabled ? (_) => onSend() : null,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: enabled ? onSend : null,
              child: Text(isSending ? 'Sending...' : 'Send'),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.lock_outline,
            size: 14,
            color: theme.disabledColor.withValues(alpha: 0.65),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final SupportMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;
    final primary = theme.colorScheme.primary;
    return Align(
      alignment: message.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.62,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: message.isMine ? primary : theme.scaffoldBackgroundColor,
          border: message.isMine
              ? null
              : Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(message.isMine ? 12 : 4),
            bottomRight: Radius.circular(message.isMine ? 4 : 12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: message.isMine ? Colors.white : null,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${message.senderName} · ${_formatDateTime(context, message.sentAt)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: message.isMine
                    ? Colors.white.withValues(alpha: 0.82)
                    : secondary,
                fontSize: 10,
              ),
            ),
          ],
        ),
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
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;
    return Container(
      constraints: const BoxConstraints(maxWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          color: secondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context)
        .extension<PatientPortalTextColors>()!
        .secondary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Text(
          'You have no support tickets yet. Create a new ticket to get started.',
          textAlign: TextAlign.center,
          style: TextStyle(color: secondary, height: 1.7),
        ),
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context)
        .extension<PatientPortalTextColors>()!
        .secondary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Text(
          'No Conversation Selected\nSelect a support ticket to view its messages.',
          textAlign: TextAlign.center,
          style: TextStyle(color: secondary, height: 1.7),
        ),
      ),
    );
  }
}

class _NoMessages extends StatelessWidget {
  const _NoMessages({required this.canSend, required this.status});

  final bool canSend;
  final String status;

  @override
  Widget build(BuildContext context) {
    final statusLower = status.toLowerCase();
    final message = canSend
        ? 'No messages yet. You can send a message below.'
        : statusLower == 'open'
        ? 'No messages yet. You can reply after Super Admin accepts your ticket.'
        : _isReadOnly(status)
        ? 'No messages yet. This conversation is read-only.'
        : 'No messages yet. Messaging is currently unavailable.';
    final secondary = Theme.of(context)
        .extension<PatientPortalTextColors>()!
        .secondary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: secondary, height: 1.7),
        ),
      ),
    );
  }
}

class _NewTicketDraft {
  const _NewTicketDraft({
    required this.category,
    required this.subject,
    required this.priority,
    required this.description,
  });

  final String category;
  final String subject;
  final String priority;
  final String description;
}

class _NewTicketDialog extends StatefulWidget {
  const _NewTicketDialog();

  @override
  State<_NewTicketDialog> createState() => _NewTicketDialogState();
}

class _NewTicketDialogState extends State<_NewTicketDialog> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _category;
  String _priority = 'Medium';

  @override
  void dispose() {
    _subjectController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _NewTicketDraft(
        category: _category!,
        subject: _subjectController.text.trim(),
        priority: _priority,
        description: _descriptionController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;
    final viewport = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 540,
          maxHeight: (viewport.height * 0.88).clamp(360, 760),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 14, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Create a Support Ticket',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Provide the details below so our team can assist you.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondary,
                            height: 1.55,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Close form',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      side: BorderSide(color: theme.colorScheme.outline),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.colorScheme.outline),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _category,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        hint: const Text('Select a category'),
                        items: SupportTicketOptions.categories
                            .map(
                              (category) => DropdownMenuItem(
                                value: category,
                                child: Text(category),
                              ),
                            )
                            .toList(),
                        validator: (value) =>
                            value == null ? 'Select a category' : null,
                        onChanged: (value) => setState(() => _category = value),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _subjectController,
                        maxLength: 160,
                        decoration: const InputDecoration(
                          labelText: 'Subject',
                          hintText: 'Enter a short title for your concern',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          counterText: '',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter a subject'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _priority,
                        decoration: const InputDecoration(
                          labelText: 'Priority',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        items: SupportTicketOptions.priorities
                            .map(
                              (priority) => DropdownMenuItem(
                                value: priority,
                                child: Text(priority),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) setState(() => _priority = value);
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descriptionController,
                        maxLength: 4000,
                        minLines: 4,
                        maxLines: 7,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          hintText: 'Describe your concern in detail...',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          alignLabelWithHint: true,
                          counterText: '',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter a description'
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: theme.colorScheme.outline),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
              child: Wrap(
                alignment: WrapAlignment.end,
                runAlignment: WrapAlignment.end,
                spacing: 10,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(82, 42),
                      foregroundColor: secondary,
                      side: BorderSide(color: theme.colorScheme.outline),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(132, 42),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    child: const Text('Submit Ticket'),
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

bool _canSendMessage(SupportTicket ticket) {
  final status = ticket.status.toLowerCase();
  return status == 'in progress' || status == 'pending';
}

bool _isReadOnly(String status) {
  final normalized = status.toLowerCase();
  return normalized == 'resolved' || normalized == 'closed';
}

String _conversationSubtitle(SupportTicket? ticket) {
  if (ticket == null) return 'Select a ticket to view your conversation.';
  if (_canSendMessage(ticket)) {
    return '${ticket.status} · ${ticket.priority} priority';
  }
  if (ticket.status.toLowerCase() == 'open') {
    return 'Waiting for Super Admin to accept your ticket.';
  }
  if (_isReadOnly(ticket.status)) {
    return '${ticket.status} · This conversation is read-only.';
  }
  return 'Messaging is currently unavailable.';
}

String _formatDateTime(BuildContext context, DateTime? date) {
  if (date == null) return 'Date unavailable';
  final local = date.toLocal();
  final time = TimeOfDay.fromDateTime(local).format(context);
  return '${MaterialLocalizations.of(context).formatMediumDate(local)} · $time';
}
