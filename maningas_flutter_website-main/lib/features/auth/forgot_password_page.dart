import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/api_failure.dart';
import 'application/patient_auth_controller.dart';
import 'application/patient_auth_scope.dart';
import 'application/patient_auth_setup.dart';
import 'login_page.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _showResetStep = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;
  bool _isSubmitting = false;
  String? _statusMessage;
  bool _statusIsError = false;
  PatientAuthController? _controller;
  bool _ownsController = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    _controller = PatientAuthScope.maybeOf(context);
    if (_controller == null) {
      _controller = createPatientAuthController();
      _ownsController = true;
    }
  }

  @override
  void dispose() {
    if (_ownsController) _controller?.dispose();
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _requestPasswordReset() async {
    FocusScope.of(context).unfocus();
    if (!_emailFormKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _statusMessage = null;
      _statusIsError = false;
    });
    try {
      final message = await _controller!.repository.requestPasswordReset(
        email: _emailController.text.trim().toLowerCase(),
      );
      if (!mounted) return;
      setState(() {
        _showResetStep = true;
        _statusMessage = message;
        _statusIsError = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _statusMessage = failure.message;
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitPasswordReset() async {
    FocusScope.of(context).unfocus();
    if (!_resetFormKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _statusMessage = null;
      _statusIsError = false;
    });
    try {
      final message = await _controller!.repository.resetPassword(
        email: _emailController.text.trim().toLowerCase(),
        otp: _codeController.text.trim(),
        newPassword: _newPasswordController.text,
      );
      if (!mounted) return;
      setState(() {
        _statusMessage = message;
        _statusIsError = false;
      });
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => LoginPage(initialMessage: message),
          ),
        );
      }
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _statusMessage = failure.message;
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _returnToEmailStep() {
    setState(() {
      _showResetStep = false;
      _statusMessage = null;
      _statusIsError = false;
    });
  }

  void _backToLogin() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    navigator.pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth <= 900;
        final smallPhone = constraints.maxWidth <= 480;
        final content = _ForgotPasswordContent(
          mobile: mobile,
          smallPhone: smallPhone,
          showResetStep: _showResetStep,
          showNewPassword: _showNewPassword,
          showConfirmPassword: _showConfirmPassword,
          statusMessage: _statusMessage,
          statusIsError: _statusIsError,
          isSubmitting: _isSubmitting,
          emailFormKey: _emailFormKey,
          resetFormKey: _resetFormKey,
          emailController: _emailController,
          codeController: _codeController,
          newPasswordController: _newPasswordController,
          confirmPasswordController: _confirmPasswordController,
          onContinue: _requestPasswordReset,
          onSubmitReset: _submitPasswordReset,
          onBackToEmail: _returnToEmailStep,
          onBackToLogin: _backToLogin,
          onToggleNewPassword: () =>
              setState(() => _showNewPassword = !_showNewPassword),
          onToggleConfirmPassword: () =>
              setState(() => _showConfirmPassword = !_showConfirmPassword),
        );

        final page = mobile
            ? content
            : SizedBox(
                height: constraints.maxHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Expanded(child: _ForgotPasswordBrandPanel()),
                    Expanded(child: SingleChildScrollView(child: content)),
                  ],
                ),
              );

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: page,
            ),
          ),
        );
      },
    );
  }
}

class _ForgotPasswordBrandPanel extends StatelessWidget {
  const _ForgotPasswordBrandPanel();

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xF52563EB), Color(0xF51D4ED8)],
                ),
              ),
            ),
          ),
          const Positioned(
            width: 420,
            height: 420,
            right: -170,
            top: -140,
            child: _BrandCircle(opacity: 0.08),
          ),
          const Positioned(
            width: 300,
            height: 300,
            left: -150,
            bottom: -120,
            child: _BrandCircle(opacity: 0.08),
          ),
          const Positioned(
            width: 180,
            height: 180,
            right: 80,
            bottom: 100,
            child: _BrandCircle(opacity: 0.05),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(60),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ClinicBrandMark(),
                    SizedBox(height: 30),
                    Text(
                      'Get back to\nyour account.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.5,
                      ),
                    ),
                    SizedBox(height: 18),
                    Text(
                      "Don't worry if you forgot your password. We can help you "
                      'regain access to your Gonzales Vision Clinic patient account.',
                      style: TextStyle(
                        color: Color(0xD9FFFFFF),
                        fontSize: 17,
                        height: 1.7,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandCircle extends StatelessWidget {
  const _BrandCircle({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: opacity),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _ClinicBrandMark extends StatelessWidget {
  const _ClinicBrandMark({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 58.0 : 78.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 15 : 20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Text(
        'G',
        style: TextStyle(
          color: const Color(0xFF2563EB),
          fontSize: compact ? 32 : 42,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ForgotPasswordContent extends StatelessWidget {
  const _ForgotPasswordContent({
    required this.mobile,
    required this.smallPhone,
    required this.showResetStep,
    required this.showNewPassword,
    required this.showConfirmPassword,
    required this.statusMessage,
    required this.statusIsError,
    required this.isSubmitting,
    required this.emailFormKey,
    required this.resetFormKey,
    required this.emailController,
    required this.codeController,
    required this.newPasswordController,
    required this.confirmPasswordController,
    required this.onContinue,
    required this.onSubmitReset,
    required this.onBackToEmail,
    required this.onBackToLogin,
    required this.onToggleNewPassword,
    required this.onToggleConfirmPassword,
  });

  final bool mobile;
  final bool smallPhone;
  final bool showResetStep;
  final bool showNewPassword;
  final bool showConfirmPassword;
  final String? statusMessage;
  final bool statusIsError;
  final bool isSubmitting;
  final GlobalKey<FormState> emailFormKey;
  final GlobalKey<FormState> resetFormKey;
  final TextEditingController emailController;
  final TextEditingController codeController;
  final TextEditingController newPasswordController;
  final TextEditingController confirmPasswordController;
  final VoidCallback? onContinue;
  final VoidCallback? onSubmitReset;
  final VoidCallback onBackToEmail;
  final VoidCallback onBackToLogin;
  final VoidCallback onToggleNewPassword;
  final VoidCallback onToggleConfirmPassword;

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = smallPhone
        ? 18.0
        : mobile
        ? 22.0
        : 30.0;
    final verticalPadding = smallPhone
        ? 28.0
        : mobile
        ? 35.0
        : 40.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      color: Colors.white,
      child: Align(
        alignment: smallPhone ? Alignment.topCenter : Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: EdgeInsets.only(top: smallPhone ? 10 : 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (mobile) ...[
                  const Row(
                    children: [
                      _ClinicBrandMark(compact: true),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Gonzales Vision Clinic',
                          style: TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 25),
                ],
                _BackToLoginLink(onPressed: onBackToLogin),
                SizedBox(height: smallPhone ? 28 : 35),
                const Center(child: _ResetIcon()),
                const SizedBox(height: 25),
                Text(
                  showResetStep ? 'Reset your password' : 'Forgot password?',
                  key: const ValueKey('forgot-password-heading'),
                  style: TextStyle(
                    color: const Color(0xFF0F172A),
                    fontSize: smallPhone ? 27 : 32,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  showResetStep
                      ? 'Enter the OTP sent to your email and create a new password.'
                      : "Enter the email address associated with your patient "
                            "account and we'll help you reset your password.",
                  style: TextStyle(
                    color: const Color(0xFF475569),
                    fontSize: smallPhone ? 14 : 15,
                    height: 1.65,
                  ),
                ),
                if (statusMessage != null) ...[
                  const SizedBox(height: 20),
                  _StatusMessage(
                    message: statusMessage!,
                    isError: statusIsError,
                  ),
                ],
                const SizedBox(height: 24),
                if (showResetStep) _buildResetForm() else _buildEmailForm(),
                if (showResetStep)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('back-to-email'),
                      onPressed: onBackToEmail,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF475569),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: const Text('Back to email'),
                    ),
                  ),
                const SizedBox(height: 25),
                Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    children: [
                      const Text(
                        'Remember your password?',
                        style: TextStyle(
                          color: Color(0xFF475569),
                          fontSize: 14,
                        ),
                      ),
                      TextButton(
                        onPressed: onBackToLogin,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF2563EB),
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Back to login',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: EdgeInsets.only(top: smallPhone ? 30 : 40),
                  padding: const EdgeInsets.only(top: 22),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  child: const Text(
                    '© 2026 Gonzales Vision Clinic.\nYour vision, our priority.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailForm() {
    return Form(
      key: emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _FormLabel('Email Address'),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: TextFormField(
              key: const ValueKey('forgot-email'),
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 14),
              autocorrect: false,
              enableSuggestions: false,
              validator: _validateEmail,
              decoration: _inputDecoration('Enter your email address'),
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 52,
            child: FilledButton(
              key: const ValueKey('forgot-continue'),
              onPressed: isSubmitting ? null : onContinue,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(isSubmitting ? 'Sending...' : 'Continue'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResetForm() {
    return Form(
      key: resetFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _FormLabel('Verification Code'),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: TextFormField(
              key: const ValueKey('reset-code'),
              controller: codeController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              style: const TextStyle(fontSize: 14),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              validator: (value) => RegExp(r'^\d{6}$').hasMatch(value ?? '')
                  ? null
                  : 'Please enter the 6-digit verification code.',
              decoration: _inputDecoration('Enter 6-digit OTP'),
            ),
          ),
          const SizedBox(height: 18),
          const _FormLabel('New Password'),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: TextFormField(
              key: const ValueKey('new-password'),
              controller: newPasswordController,
              obscureText: !showNewPassword,
              textInputAction: TextInputAction.next,
              style: const TextStyle(fontSize: 14),
              validator: _validatePassword,
              decoration: _inputDecoration(
                'Enter new password',
                suffixIcon: IconButton(
                  tooltip: showNewPassword ? 'Hide password' : 'Show password',
                  onPressed: onToggleNewPassword,
                  icon: Icon(
                    showNewPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const _FormLabel('Confirm New Password'),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: TextFormField(
              key: const ValueKey('confirm-password'),
              controller: confirmPasswordController,
              obscureText: !showConfirmPassword,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 14),
              validator: (value) {
                if ((value ?? '').isEmpty) {
                  return 'Please confirm your new password.';
                }
                if (value != newPasswordController.text) {
                  return 'The passwords do not match.';
                }
                return null;
              },
              decoration: _inputDecoration(
                'Confirm new password',
                suffixIcon: IconButton(
                  tooltip: showConfirmPassword
                      ? 'Hide password'
                      : 'Show password',
                  onPressed: onToggleConfirmPassword,
                  icon: Icon(
                    showConfirmPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 52,
            child: FilledButton(
              key: const ValueKey('reset-submit'),
              onPressed: isSubmitting ? null : onSubmitReset,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(isSubmitting ? 'Changing...' : 'Change Password'),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackToLoginLink extends StatelessWidget {
  const _BackToLoginLink({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF475569),
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 24),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('←'),
            SizedBox(width: 8),
            Text(
              'Back to login',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResetIcon extends StatelessWidget {
  const _ResetIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Icon(
        Icons.autorenew_rounded,
        size: 30,
        color: Color(0xFF2563EB),
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? const Color(0xFFDC2626) : const Color(0xFF166534);
    final fill = isError ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4);
    final border = isError ? const Color(0xFFFECACA) : const Color(0xFFBBF7D0);
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('forgot-status'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          message,
          style: TextStyle(color: color, fontSize: 13, height: 1.5),
        ),
      ),
    );
  }
}

class _FormLabel extends StatelessWidget {
  const _FormLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF0F172A),
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

InputDecoration _inputDecoration(String hint, {Widget? suffixIcon}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF2563EB)),
    ),
  );
}

String? _validateEmail(String? value) {
  final email = (value ?? '').trim();
  if (email.isEmpty) return 'Please enter your email address.';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
    return 'Please enter a valid email address.';
  }
  return null;
}

String? _validatePassword(String? value) {
  final password = value ?? '';
  if (password.isEmpty) return 'Please enter your new password.';
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
