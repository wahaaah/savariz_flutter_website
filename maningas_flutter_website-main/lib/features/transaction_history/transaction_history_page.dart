import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/responsive.dart';
import '../../app/theme.dart';
import '../../core/network/api_failure.dart';
import '../auth/application/patient_auth_controller.dart';
import '../auth/application/patient_auth_scope.dart';
import '../auth/domain/patient_session.dart';
import 'transaction_record.dart';
import 'transaction_history_repository.dart';

enum TransactionHistoryPresentationState {
  ready,
  loading,
  error,
  authenticationRequired,
}

class TransactionHistoryPage extends StatefulWidget {
  const TransactionHistoryPage({
    this.transactions,
    this.presentationState,
    super.key,
  });

  final List<TransactionRecord>? transactions;
  final TransactionHistoryPresentationState? presentationState;

  @override
  State<TransactionHistoryPage> createState() => _TransactionHistoryPageState();
}

class _TransactionHistoryPageState extends State<TransactionHistoryPage> {
  static const _pageSize = 10;
  int _currentPage = 1;
  PatientAuthController? _controller;
  TransactionHistoryRepository? _repository;
  List<TransactionRecord> _transactions = const [];
  TransactionHistoryPresentationState _loadState =
      TransactionHistoryPresentationState.ready;
  String? _errorMessage;
  String? _requestedSessionKey;
  Timer? _refreshTimer;
  bool _requestInProgress = false;
  int _loadGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = PatientAuthScope.maybeOf(context);
    final repository = PatientAuthScope.transactionsOf(context);
    if (controller != _controller) {
      _controller?.removeListener(_handleSessionChange);
      _controller = controller;
      _controller?.addListener(_handleSessionChange);
    }
    if (repository != _repository) {
      _repository = repository;
      _requestedSessionKey = null;
    }
    if (widget.transactions == null && widget.presentationState == null) {
      _loadForCurrentSession();
    }
  }

  @override
  void didUpdateWidget(covariant TransactionHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.transactions != oldWidget.transactions) {
      _transactions = widget.transactions ?? const [];
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
    if (widget.transactions == null && widget.presentationState == null) {
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
          TransactionHistoryPresentationState.authenticationRequired) {
        setState(() {
          _transactions = const [];
          _loadState =
              TransactionHistoryPresentationState.authenticationRequired;
          _errorMessage = 'Transaction history is not connected to the API.';
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
          TransactionHistoryPresentationState.authenticationRequired) {
        setState(() {
          _loadState =
              TransactionHistoryPresentationState.authenticationRequired;
          _errorMessage = null;
          _transactions = const [];
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
      (_) => _refreshTransactions(),
    );
    _fetchTransactions(repository, session, ++_loadGeneration);
  }

  void _refreshTransactions() {
    if (_requestInProgress ||
        widget.transactions != null ||
        widget.presentationState != null) {
      return;
    }
    final repository = _repository;
    final session = _controller?.currentSession;
    if (repository == null || session == null) return;
    _fetchTransactions(
      repository,
      session,
      ++_loadGeneration,
      silent: true,
    );
  }

  Future<void> _fetchTransactions(
    TransactionHistoryRepository repository,
    PatientSession session,
    int generation,
    {bool silent = false}
  ) async {
    _requestInProgress = true;
    if (mounted) {
      setState(() {
        if (!silent || _transactions.isEmpty) {
          _loadState = TransactionHistoryPresentationState.loading;
        }
        _errorMessage = null;
      });
    }
    try {
      final records = await repository.getTransactions(
        patientId: session.patientId,
        token: session.token,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _transactions = records;
        _loadState = TransactionHistoryPresentationState.ready;
        if (!silent) _currentPage = 1;
      });
    } on ApiFailure catch (failure) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadState = failure.statusCode == 401 || failure.statusCode == 403
            ? TransactionHistoryPresentationState.authenticationRequired
            : TransactionHistoryPresentationState.error;
        _errorMessage = failure.message;
      });
    } on Exception catch (error, stackTrace) {
      if (!mounted || generation != _loadGeneration) return;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError(
            'Unexpected transaction history failure (${error.runtimeType}).',
          ),
          stack: stackTrace,
          library: 'patient transaction history',
        ),
      );
      setState(() {
        _loadState = TransactionHistoryPresentationState.error;
        _errorMessage = 'Unable to load transaction history. Please try again.';
      });
    } finally {
      if (generation == _loadGeneration) _requestInProgress = false;
    }
  }

  void _retry() {
    _requestedSessionKey = null;
    _loadForCurrentSession();
  }

  List<TransactionRecord> get _sortedTransactions {
    final records = (widget.transactions ?? _transactions).toList();
    records.sort((a, b) {
      final aDate = a.date;
      final bDate = b.date;
      if (aDate == null) return bDate == null ? 0 : 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    return records;
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
    final transactions = _sortedTransactions;
    final pageCount = (transactions.length / _pageSize).ceil();
    final safePage = pageCount == 0 ? 1 : _currentPage.clamp(1, pageCount);
    final pageTransactions = transactions
        .skip((safePage - 1) * _pageSize)
        .take(_pageSize)
        .toList();

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
              _BillingRecordsCard(
                transactions: pageTransactions,
                totalItems: transactions.length,
                page: safePage,
                pageSize: _pageSize,
                onPageChanged: (page) => setState(() => _currentPage = page),
                presentationState: widget.presentationState ?? _loadState,
                errorMessage: _errorMessage,
                onRetry: _retry,
              ),
            ],
          ),
        ),
      ),
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
          'Transaction History',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontSize: compact ? 28 : 36,
            height: 1.2,
            letterSpacing: -1.2,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Review your billing and payment activity for clinic services.',
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

class _BillingRecordsCard extends StatelessWidget {
  const _BillingRecordsCard({
    required this.transactions,
    required this.totalItems,
    required this.page,
    required this.pageSize,
    required this.onPageChanged,
    required this.presentationState,
    required this.errorMessage,
    required this.onRetry,
  });

  final List<TransactionRecord> transactions;
  final int totalItems;
  final int page;
  final int pageSize;
  final ValueChanged<int> onPageChanged;
  final TransactionHistoryPresentationState presentationState;
  final String? errorMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          const _BillingCardHeader(),
          if (presentationState == TransactionHistoryPresentationState.ready &&
              totalItems > 0)
            _TransactionPagination(
              page: page,
              pageSize: pageSize,
              totalItems: totalItems,
              onPageChanged: onPageChanged,
            ),
          switch (presentationState) {
            TransactionHistoryPresentationState.ready =>
              transactions.isEmpty
                  ? const _EmptyState()
                  : _TransactionList(transactions: transactions),
            TransactionHistoryPresentationState.loading => _PreviewState(
              title: 'Loading transaction history...',
              detail: 'Fetching your transaction history.',
            ),
            TransactionHistoryPresentationState.error => _PreviewState(
              title: 'Unable to load transaction history',
              detail:
                  errorMessage ??
                  'Unable to load transaction history. Please try again.',
              error: true,
              onRetry: onRetry,
            ),
            TransactionHistoryPresentationState.authenticationRequired =>
              _PreviewState(
                title: 'Sign in required',
                detail:
                    errorMessage ??
                    'Sign in again to view your transaction history.',
                error: true,
                onRetry: onRetry,
              ),
          },
        ],
      ),
    );
  }
}

class _BillingCardHeader extends StatelessWidget {
  const _BillingCardHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;
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
              Icons.receipt_long_outlined,
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
                  'Billing records',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Payments and transaction activity linked to your patient account.',
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

class _TransactionPagination extends StatelessWidget {
  const _TransactionPagination({
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
    final compact = MediaQuery.sizeOf(context).width <= 680;
    final totalPages = (totalItems / pageSize).ceil();
    final start = (page - 1) * pageSize + 1;
    final end = (page * pageSize).clamp(0, totalItems);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
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
            spacing: 7,
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
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: enabled ? onPressed : null,
    style: _pagerStyle(context, compact),
    child: Text(label),
  );
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

class _TransactionList extends StatelessWidget {
  const _TransactionList({required this.transactions});

  final List<TransactionRecord> transactions;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 680;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        children: [
          for (var index = 0; index < transactions.length; index++) ...[
            if (index > 0) const SizedBox(height: 12),
            _TransactionCard(
              transaction: transactions[index],
              compact: compact,
            ),
          ],
        ],
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({required this.transaction, required this.compact});

  final TransactionRecord transaction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;

    return Container(
      padding: EdgeInsets.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        color: _surfaceSoft(context),
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 540;
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.description,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_formatDate(transaction.date)} · Ref: ${transaction.reference}',
                    softWrap: true,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      fontSize: 13,
                      height: 1.55,
                    ),
                  ),
                ],
              );
              final amountAndStatus = Column(
                crossAxisAlignment: narrow
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatCurrency(transaction.total),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 20,
                      letterSpacing: -0.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _StatusBadge(status: transaction.status),
                ],
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    details,
                    const SizedBox(height: 12),
                    amountAndStatus,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: details),
                  const SizedBox(width: 20),
                  amountAndStatus,
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Divider(height: 1, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            'ITEMS',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          if (transaction.items.isEmpty)
            Text(
              'No item details available.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                fontSize: 13,
              ),
            )
          else
            for (final item in transaction.items) ...[
              _ChargeRow(
                label:
                    '${item.name}${item.quantity == null ? '' : ' × ${item.quantity}'}',
                value: _formatCurrency(item.total),
              ),
              const SizedBox(height: 7),
            ],
          const SizedBox(height: 8),
          Divider(
            height: 1,
            color: theme.colorScheme.outline.withValues(alpha: 0.75),
          ),
          const SizedBox(height: 10),
          _ChargeRow(
            label: 'Subtotal',
            value: _formatCurrency(transaction.subtotal),
            secondary: true,
          ),
          if (transaction.discountAmount != null &&
              transaction.discountAmount! > 0) ...[
            const SizedBox(height: 8),
            _ChargeRow(
              label:
                  '${transaction.discountName ?? 'Discount'}'
                  '${transaction.discountPercent != null && transaction.discountPercent! > 0 ? ' (${_formatNumber(transaction.discountPercent!)}%)' : ''}',
              value: '-${_formatCurrency(transaction.discountAmount)}',
              discount: true,
            ),
          ],
          const SizedBox(height: 8),
          _ChargeRow(
            label: 'VAT',
            value: _formatCurrency(transaction.vat),
            secondary: true,
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: theme.colorScheme.outline),
          const SizedBox(height: 10),
          _ChargeRow(
            label: 'Total',
            value: _formatCurrency(transaction.total),
            total: true,
          ),
        ],
      ),
    );
  }
}

class _ChargeRow extends StatelessWidget {
  const _ChargeRow({
    required this.label,
    required this.value,
    this.secondary = false,
    this.discount = false,
    this.total = false,
  });

  final String label;
  final String value;
  final bool secondary;
  final bool discount;
  final bool total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<PatientPortalTextColors>()!;
    final color = discount
        ? theme.brightness == Brightness.light
              ? const Color(0xFFDC2626)
              : const Color(0xFFF87171)
        : secondary
        ? colors.secondary
        : theme.colorScheme.onSurface;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            softWrap: true,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontSize: total ? 15 : 13,
              height: 1.5,
              fontWeight: total ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          textAlign: TextAlign.end,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontSize: total ? 15 : 13,
            height: 1.5,
            fontWeight: total ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No transaction records available',
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'There are no payment or billing records currently linked to this patient account.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: secondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewState extends StatelessWidget {
  const _PreviewState({
    required this.title,
    required this.detail,
    this.error = false,
    this.onRetry,
  });

  final String title;
  final String detail;
  final bool error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;
    final color = error
        ? theme.brightness == Brightness.light
              ? const Color(0xFFDC2626)
              : const Color(0xFFF87171)
        : secondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: error ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            detail,
            style: theme.textTheme.bodySmall?.copyWith(color: secondary),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
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
  switch (status.trim().toLowerCase()) {
    case 'paid':
    case 'completed':
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
    case 'voided':
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
    default:
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
}

String _formatCurrency(double? value) {
  if (value == null) return 'Not available';
  final fixed = value.toStringAsFixed(2);
  final parts = fixed.split('.');
  final digits = parts.first;
  final grouped = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      grouped.write(',');
    }
    grouped.write(digits[index]);
  }
  return '₱${grouped.toString()}.${parts[1]}';
}

String _formatNumber(double value) =>
    value == value.truncateToDouble() ? value.toInt().toString() : '$value';

String _formatDate(DateTime? date) => date == null
    ? 'Date unavailable'
    : '${_monthShort(date.month)} ${date.day}, ${date.year}';

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
