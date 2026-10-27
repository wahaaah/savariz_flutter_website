import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/responsive.dart';
import '../../app/theme.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _otpController = TextEditingController();

  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;
  bool _showOtpStep = false;
  bool _showSuccessStep = false;
  String? _status;
  String? _otpStatus;
  bool _otpStatusIsError = false;
  Timer? _resendTimer;
  int _resendSeconds = 0;

  @override
  void dispose() {
    _currentPasswordController
      ..clear()
      ..dispose();
    _newPasswordController
      ..clear()
      ..dispose();
    _confirmPasswordController
      ..clear()
      ..dispose();
    _otpController
      ..clear()
      ..dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  String? _validateRequired(String? value, String label) {
    if ((value ?? '').isEmpty) return 'Please enter your $label.';
    return null;
  }

  String? _validateNewPassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Please enter your new password.';
    if (password == _currentPasswordController.text) {
      return 'New password must be different from your current password.';
    }
    if (password.length < 8) {
      return 'Password must be at least 8 characters long.';
    }
    if (password.length > 128) {
      return 'Password must not exceed 128 characters.';
    }
    if (RegExp(r'\s').hasMatch(password)) {
      return 'Password must not contain spaces.';
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'Password must contain at least one lowercase letter.';
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Password must contain at least one uppercase letter.';
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'Password must contain at least one number.';
    }
    return null;
  }

  String? _validateConfirmation(String? value) {
    if ((value ?? '').isEmpty) {
      return 'Please confirm your new password.';
    }
    if (value != _newPasswordController.text) {
      return 'The passwords do not match.';
    }
    return null;
  }

  void _changePassword() {
    FocusScope.of(context).unfocus();
    final valid = _formKey.currentState!.validate();
    if (!valid) {
      setState(() => _status = null);
      return;
    }
    setState(() {
      _status = 'Password changes are not connected to the clinic API. Nothing was changed.';
      _otpStatus = null;
      _otpStatusIsError = false;
      _showOtpStep = false;
      _showSuccessStep = false;
    });
  }

  void _verifyOtp() {
    FocusScope.of(context).unfocus();
    if (!RegExp(r'^\d{6}$').hasMatch(_otpController.text)) {
      setState(() {
        _otpStatus = 'Please enter the complete 6-digit code.';
        _otpStatusIsError = true;
      });
      return;
    }
    setState(() {
      _otpStatus =
          'Password change verification is not connected to the clinic API.';
      _otpStatusIsError = true;
    });
  }

  void _cancelOtp() {
    _resendTimer?.cancel();
    _resendTimer = null;
    _clearPasswordValues();
    _otpController.clear();
    setState(() {
      _resendSeconds = 0;
      _otpStatus = null;
      _otpStatusIsError = false;
      _showOtpStep = false;
      _showSuccessStep = false;
    });
  }

  void _resendVerificationCode() {
    if (_resendSeconds > 0) return;
    setState(() {
      _otpStatus =
          'Verification-code resend is not connected to the clinic API.';
      _otpStatusIsError = true;
    });
  }

  void _returnToProfile() {
    _clearPasswordValues();
    _otpController.clear();
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    setState(() {
      _showSuccessStep = false;
      _status = 'Password changes are not connected to the clinic API.';
    });
  }

  void _cancel() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    _clearPasswordValues();
    setState(() {
      _status = 'Password entries were cleared. No changes were saved.';
    });
  }

  void _clearPasswordValues() {
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
    _formKey.currentState?.reset();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width <= PatientPortalBreakpoints.mobile;
    final pagePadding = compact
        ? 16.0
        : width <= PatientPortalBreakpoints.mobileNavigation
        ? 22.0
        : 30.0;

    return Scaffold(
      body: SafeArea(
        child: _showOtpStep
            ? _buildOtpStep(compact: compact, pagePadding: pagePadding)
            : _showSuccessStep
            ? _buildSuccessStep(compact: compact, pagePadding: pagePadding)
            : SingleChildScrollView(
                key: const ValueKey('change-password-scroll'),
                padding: EdgeInsets.fromLTRB(
                  pagePadding,
                  compact ? 22 : 30,
                  pagePadding,
                  compact ? 32 : 45,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PageHeader(compact: compact),
                          const SizedBox(height: 22),
                          _PasswordCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _PasswordField(
                                  key: const ValueKey('current-password'),
                                  label: 'Current Password',
                                  hint: 'Enter your current password',
                                  controller: _currentPasswordController,
                                  visible: _showCurrentPassword,
                                  onToggleVisibility: () => setState(
                                    () => _showCurrentPassword =
                                        !_showCurrentPassword,
                                  ),
                                  validator: (value) => _validateRequired(
                                    value,
                                    'current password',
                                  ),
                                  textInputAction: TextInputAction.next,
                                ),
                                const SizedBox(height: 18),
                                _PasswordField(
                                  key: const ValueKey('new-password'),
                                  label: 'New Password',
                                  hint: 'Enter your new password',
                                  controller: _newPasswordController,
                                  visible: _showNewPassword,
                                  onToggleVisibility: () => setState(
                                    () => _showNewPassword = !_showNewPassword,
                                  ),
                                  validator: _validateNewPassword,
                                  onChanged: (_) {
                                    if (_formKey.currentState?.validate() ??
                                        false) {
                                      setState(() => _status = null);
                                    }
                                  },
                                  textInputAction: TextInputAction.next,
                                ),
                                const SizedBox(height: 18),
                                _PasswordField(
                                  key: const ValueKey('confirm-new-password'),
                                  label: 'Confirm New Password',
                                  hint: 'Confirm your new password',
                                  controller: _confirmPasswordController,
                                  visible: _showConfirmPassword,
                                  onToggleVisibility: () => setState(
                                    () => _showConfirmPassword =
                                        !_showConfirmPassword,
                                  ),
                                  validator: _validateConfirmation,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _changePassword(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (_status != null) ...[
                            _StatusMessage(message: _status!),
                            const SizedBox(height: 14),
                          ],
                          LayoutBuilder(
                            builder: (context, buttonConstraints) {
                              final vertical = buttonConstraints.maxWidth < 430;
                              final changeButton = FilledButton.icon(
                                key: const ValueKey('change-password-submit'),
                                onPressed: _changePassword,
                                icon: const Icon(Icons.lock_reset_rounded),
                                label: const Text('Change Password'),
                              );
                              final cancelButton = OutlinedButton.icon(
                                key: const ValueKey('change-password-cancel'),
                                onPressed: _cancel,
                                icon: const Icon(Icons.close_rounded),
                                label: const Text('Cancel'),
                              );
                              if (vertical) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SizedBox(height: 48, child: changeButton),
                                    const SizedBox(height: 10),
                                    SizedBox(height: 46, child: cancelButton),
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 48,
                                      child: changeButton,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: SizedBox(
                                      height: 48,
                                      child: cancelButton,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Password rules are not confirmed against the clinic account policy.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .extension<PatientPortalTextColors>()!
                                      .secondary,
                                  height: 1.5,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildOtpStep({required bool compact, required double pagePadding}) {
    final secondary = Theme.of(context)
        .extension<PatientPortalTextColors>()!
        .secondary;
    return SingleChildScrollView(
      key: const ValueKey('change-password-otp-scroll'),
      padding: EdgeInsets.fromLTRB(
        pagePadding,
        compact ? 22 : 30,
        pagePadding,
        compact ? 32 : 45,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('change-password-otp-cancel'),
                  onPressed: _cancelOtp,
                  icon: const Icon(Icons.arrow_back, size: 17),
                  label: const Text('Cancel and return'),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Verify Change Password',
                key: const ValueKey('change-password-otp-heading'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: compact ? 25 : 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Password changes are not connected to the clinic API.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: secondary, height: 1.5),
              ),
              const SizedBox(height: 20),
              _PasswordCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Password changes are not connected to the clinic API. '
                      'No code has been sent.',
                      key: ValueKey('change-password-api-notice'),
                      style: TextStyle(
                        color: Color(0xFF1D4ED8),
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '6-digit code',
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('change-password-otp-code'),
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      maxLength: 6,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 8,
                      ),
                      onChanged: (_) {
                        if (_otpStatusIsError) {
                          setState(() {
                            _otpStatus = null;
                            _otpStatusIsError = false;
                          });
                        }
                      },
                      onSubmitted: (_) => _verifyOtp(),
                      decoration: const InputDecoration(
                        hintText: '••••••',
                        counterText: '',
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    if (_otpStatus != null) ...[
                      const SizedBox(height: 12),
                      _StatusMessage(
                        message: _otpStatus!,
                        isError: _otpStatusIsError,
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        key: const ValueKey('change-password-otp-verify'),
                        onPressed: _verifyOtp,
                        icon: const Icon(Icons.verified_outlined),
                        label: const Text('Verify Code'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        key: const ValueKey('change-password-otp-resend'),
                        onPressed: _resendSeconds > 0
                            ? null
                            : _resendVerificationCode,
                        child: Text(
                          _resendSeconds > 0
                              ? 'Resend code in ${_resendSeconds}s'
                              : 'Resend code',
                        ),
                      ),
                    ),
                    if (_resendSeconds > 0)
                      Text(
                        'LOCAL SIMULATION: Resend available in '
                        '${_resendSeconds}s. No code was sent.',
                        key: const ValueKey('change-password-otp-countdown'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: secondary, fontSize: 12),
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

  Widget _buildSuccessStep({
    required bool compact,
    required double pagePadding,
  }) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      key: const ValueKey('change-password-success-scroll'),
      padding: EdgeInsets.fromLTRB(
        pagePadding,
        compact ? 22 : 30,
        pagePadding,
        compact ? 32 : 45,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              Icon(
                Icons.check_circle_outline,
                size: 58,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 18),
              Text(
                'Change Password',
                key: const ValueKey('change-password-success-heading'),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontSize: compact ? 25 : 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              const _StatusMessage(
                message:
                    'Password changes are not connected to the clinic API. '
                    'No password was changed.',
                isSuccess: true,
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 48,
                child: FilledButton(
                  key: const ValueKey('change-password-return-profile'),
                  onPressed: _returnToProfile,
                  child: const Text('Return to My Profile'),
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
  const _PageHeader({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;
    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 7, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          'GONZALES VISION CLINIC',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
    final unavailableBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'NOT CONNECTED',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (compact) ...[
          brand,
          const SizedBox(height: 8),
          unavailableBadge,
        ] else
          Row(children: [brand, const Spacer(), unavailableBadge]),
        const SizedBox(height: 10),
        Text(
          'Change Password',
          key: const ValueKey('change-password-heading'),
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: compact ? 26 : 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'Password changes are not connected to the clinic API.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: secondary,
            height: 1.55,
          ),
        ),
      ],
    );
  }
}

class _PasswordCard extends StatelessWidget {
  const _PasswordCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    required this.visible,
    required this.onToggleVisibility,
    required this.validator,
    required this.textInputAction,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final bool visible;
  final VoidCallback onToggleVisibility;
  final FormFieldValidator<String> validator;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
      SizedBox(
        height: 52,
        child: TextFormField(
          key: ValueKey('change-password-$label'),
          controller: controller,
          obscureText: !visible,
          textInputAction: textInputAction,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          validator: validator,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 14,
            ),
            suffixIcon: IconButton(
              key: ValueKey('change-password-toggle-$label'),
              tooltip: visible ? 'Hide password' : 'Show password',
              onPressed: onToggleVisibility,
              icon: Icon(
                visible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 19,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.message,
    this.isError = false,
    this.isSuccess = false,
  });

  final String message;
  final bool isError;
  final bool isSuccess;

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? const Color(0xFFDC2626)
        : isSuccess
        ? const Color(0xFF166534)
        : const Color(0xFF1D4ED8);
    final background = isError
        ? const Color(0xFFFEF2F2)
        : isSuccess
        ? const Color(0xFFF0FDF4)
        : const Color(0xFFEFF6FF);
    final border = isError
        ? const Color(0xFFFECACA)
        : isSuccess
        ? const Color(0xFFBBF7D0)
        : const Color(0xFFBFDBFE);
    return Container(
      key: const ValueKey('change-password-status'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
