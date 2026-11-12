import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_failure.dart';
import 'application/patient_auth_controller.dart';
import 'application/patient_auth_scope.dart';
import 'application/patient_auth_setup.dart';
import 'login_page.dart';
import 'registration_page.dart';

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({super.key, this.email});

  final String? email;

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _focusNodes = List.generate(6, (_) => FocusNode());
  Timer? _resendTimer;
  int _resendSeconds = 0;
  String? _status;
  bool _statusIsError = false;
  PatientAuthController? _authController;
  bool _ownsController = false;
  bool _isSubmitting = false;
  bool _isResending = false;

  String get _email {
    final value = widget.email?.trim();
    return value == null || value.isEmpty ? 'your email address' : value;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_authController != null) return;
    _authController = PatientAuthScope.maybeOf(context);
    if (_authController == null) {
      _authController = createPatientAuthController();
      _ownsController = true;
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    if (_ownsController) _authController?.dispose();
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((controller) => controller.text).join();

  void _handleDigitChanged(int index, String value) {
    if (value.length > 1) {
      _pasteDigits(index, value);
      return;
    }
    setState(() {
      _controllers[index].text = value;
      _clearStatus();
    });
    if (value.isNotEmpty && index < _focusNodes.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }
  }

  void _pasteDigits(int startIndex, String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      setState(() {
        _controllers[startIndex].clear();
        _clearStatus();
      });
      return;
    }
    final available = _controllers.length - startIndex;
    final pasted = digits.substring(0, digits.length.clamp(0, available));
    setState(() {
      for (var offset = 0; offset < available; offset++) {
        final targetIndex = startIndex + offset;
        _controllers[targetIndex].text = offset < pasted.length
            ? pasted[offset]
            : '';
      }
      _clearStatus();
    });
    final focusIndex = (startIndex + pasted.length).clamp(
      startIndex,
      _focusNodes.length - 1,
    );
    _focusNodes[focusIndex].requestFocus();
  }

  KeyEventResult _handleKeyEvent(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft && index > 0) {
      _focusNodes[index - 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
        index < _focusNodes.length - 1) {
      _focusNodes[index + 1].requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _clearStatus() {
    _status = null;
    _statusIsError = false;
  }

  Future<void> _verifyCode() async {
    FocusScope.of(context).unfocus();
    if (widget.email == null || widget.email!.trim().isEmpty) {
      setState(() {
        _status = 'Email address is unavailable. Return to registration.';
        _statusIsError = true;
      });
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(_code)) {
      setState(() {
        _status = 'Please enter the complete 6-digit verification code.';
        _statusIsError = true;
      });
      final emptyIndex = _controllers.indexWhere(
        (controller) => controller.text.isEmpty,
      );
      if (emptyIndex >= 0) _focusNodes[emptyIndex].requestFocus();
      return;
    }
    if (_isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _clearStatus();
    });
    try {
      final result = await _authController!.verifyEmail(
        email: _email,
        otp: _code,
      );
      if (!mounted) return;
      if (result.session != null) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        Navigator.of(context).pushAndRemoveUntil<void>(
          MaterialPageRoute<void>(
            builder: (_) => LoginPage(initialMessage: result.message),
          ),
          (_) => false,
        );
      }
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _status = failure.message;
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _resendCode() async {
    if (_resendSeconds > 0 || _isResending) return;
    if (widget.email == null || widget.email!.trim().isEmpty) {
      setState(() {
        _status = 'Email address is unavailable. Return to registration.';
        _statusIsError = true;
      });
      return;
    }
    setState(() {
      _isResending = true;
      _clearStatus();
    });
    try {
      final result = await _authController!.resendVerification(email: _email);
      if (!mounted) return;
      if (result.emailVerified) {
        setState(() {
          _status = result.message;
          _statusIsError = false;
        });
        return;
      }
      _startResendCooldown(
        result.message,
      );
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _status = failure.message;
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  void _startResendCooldown(String status) {
    _resendTimer?.cancel();
    setState(() {
      for (final controller in _controllers) {
        controller.clear();
      }
      _resendSeconds = 30;
      _status = status;
      _statusIsError = false;
    });
    _focusNodes.first.requestFocus();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendSeconds--;
        if (_resendSeconds <= 0) {
          _resendSeconds = 0;
          timer.cancel();
          _resendTimer = null;
        }
      });
    });
  }

  void _backToRegistration() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    navigator.pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const RegistrationPage()),
    );
  }

  void _backToLogin() {
    Navigator.of(context).pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final tablet = width <= 900;
        final phone = width <= 480;
        final narrowPhone = width <= 350;
        final form = _VerificationForm(
          email: _email,
          isBusy: _isSubmitting || _isResending,
          mobileBrand: tablet,
          phone: phone,
          narrowPhone: narrowPhone,
          controllers: _controllers,
          focusNodes: _focusNodes,
          resendSeconds: _resendSeconds,
          status: _status,
          statusIsError: _statusIsError,
          onDigitChanged: _handleDigitChanged,
          onKeyEvent: _handleKeyEvent,
          onVerify: _verifyCode,
          onResend: _resendCode,
          onBackToRegistration: _backToRegistration,
          onBackToLogin: _backToLogin,
        );
        final content = tablet
            ? form
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Expanded(
                      child: _VerificationBrandPanel(
                        key: ValueKey('verify-brand-panel'),
                      ),
                    ),
                    Expanded(child: form),
                  ],
                ),
              );
        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: content,
            ),
          ),
        );
      },
    );
  }
}

class _VerificationBrandPanel extends StatelessWidget {
  const _VerificationBrandPanel({super.key});

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
                      'Verify your\nemail address.',
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
                      'Enter the verification code sent to your email address.',
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
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: opacity),
      shape: BoxShape.circle,
    ),
  );
}

class _ClinicBrandMark extends StatelessWidget {
  const _ClinicBrandMark();

  @override
  Widget build(BuildContext context) => Container(
    width: 78,
    height: 78,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(
          color: Color(0x26000000),
          blurRadius: 35,
          offset: Offset(0, 15),
        ),
      ],
    ),
    child: const Text(
      'G',
      style: TextStyle(
        color: Color(0xFF2563EB),
        fontSize: 42,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _VerificationForm extends StatelessWidget {
  const _VerificationForm({
    required this.email,
    required this.isBusy,
    required this.mobileBrand,
    required this.phone,
    required this.narrowPhone,
    required this.controllers,
    required this.focusNodes,
    required this.resendSeconds,
    required this.status,
    required this.statusIsError,
    required this.onDigitChanged,
    required this.onKeyEvent,
    required this.onVerify,
    required this.onResend,
    required this.onBackToRegistration,
    required this.onBackToLogin,
  });

  final String email;
  final bool isBusy;
  final bool mobileBrand;
  final bool phone;
  final bool narrowPhone;
  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final int resendSeconds;
  final String? status;
  final bool statusIsError;
  final void Function(int index, String value) onDigitChanged;
  final KeyEventResult Function(int index, KeyEvent event) onKeyEvent;
  final VoidCallback onVerify;
  final VoidCallback onResend;
  final VoidCallback onBackToRegistration;
  final VoidCallback onBackToLogin;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('verify-form-area'),
    constraints: const BoxConstraints(minHeight: 0),
    color: Colors.white,
    padding: EdgeInsets.symmetric(
      horizontal: phone ? 18 : 30,
      vertical: phone ? 28 : 40,
    ),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (mobileBrand) ...[
              const _MobileBrandMark(),
              const SizedBox(height: 25),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('verify-back-registration'),
                onPressed: onBackToRegistration,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF475569),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Text('←', style: TextStyle(fontSize: 18)),
                label: const Text(
                  'Back to registration',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            SizedBox(height: phone ? 28 : 35),
            Text(
              'Verify your email',
              key: const ValueKey('verify-heading'),
              style: TextStyle(
                color: const Color(0xFF0F172A),
                fontSize: phone ? 27 : 32,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(height: 12),
            Text.rich(
              key: const ValueKey('verify-email-description'),
              TextSpan(
                text: 'Enter the 6-digit verification code for ',
                children: [
                  TextSpan(
                    text: email,
                    style: const TextStyle(
                      color: Color(0xFF2563EB),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
              style: TextStyle(
                color: const Color(0xFF475569),
                fontSize: phone ? 14 : 15,
                height: 1.65,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              key: const ValueKey('verify-api-notice'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                border: Border.all(color: const Color(0xFFBFDBFE)),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                'Enter the code sent to your email. The clinic service must confirm it before your account can be activated.',
                style: TextStyle(
                  color: Color(0xFF1D4ED8),
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
            if (status != null) ...[
              const SizedBox(height: 22),
              _VerificationStatus(
                message: status!,
                isError: statusIsError,
                isSuccess: false,
              ),
            ],
            SizedBox(height: status == null ? 32 : 22),
            const Text(
              'Verification code',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var index = 0; index < controllers.length; index++) ...[
                  if (index > 0)
                    SizedBox(
                      width: narrowPhone
                          ? 5
                          : phone
                          ? 7
                          : 10,
                    ),
                  Expanded(
                    child: _OtpInput(
                      index: index,
                      height: narrowPhone
                          ? 50
                          : phone
                          ? 55
                          : 62,
                      controller: controllers[index],
                      focusNode: focusNodes[index],
                      onChanged: (value) => onDigitChanged(index, value),
                      onKeyEvent: (event) => onKeyEvent(index, event),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 26),
            SizedBox(
              height: 52,
              child: FilledButton(
                key: const ValueKey('verify-email-submit'),
                onPressed: isBusy ? null : onVerify,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Verify Email',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 5,
                children: [
                  const Text(
                    "Didn't receive the code?",
                    style: TextStyle(color: Color(0xFF475569), fontSize: 14),
                  ),
                  TextButton(
                    key: const ValueKey('verify-resend'),
                    onPressed: resendSeconds > 0 || isBusy ? null : onResend,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF2563EB),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('Resend code'),
                  ),
                ],
              ),
            ),
            if (resendSeconds > 0) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  'You can resend in ${resendSeconds}s',
                  key: const ValueKey('verify-countdown'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 40),
            Container(
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
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                key: const ValueKey('verify-back-login'),
                onPressed: onBackToLogin,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF475569),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Back to login'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MobileBrandMark extends StatelessWidget {
  const _MobileBrandMark();

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('verify-mobile-brand-mark'),
    width: 58,
    height: 58,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFEFF6FF),
      borderRadius: BorderRadius.circular(15),
    ),
    child: const Text(
      'G',
      style: TextStyle(
        color: Color(0xFF2563EB),
        fontSize: 32,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _OtpInput extends StatelessWidget {
  const _OtpInput({
    required this.index,
    required this.height,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onKeyEvent,
  });

  final int index;
  final double height;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final KeyEventResult Function(KeyEvent event) onKeyEvent;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Focus(
      onKeyEvent: (_, event) => onKeyEvent(event),
      child: TextField(
        key: ValueKey('verify-digit-$index'),
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        textInputAction: index == 5
            ? TextInputAction.done
            : TextInputAction.next,
        autofillHints: index == 0 ? const [AutofillHints.oneTimeCode] : null,
        autocorrect: false,
        enableSuggestions: false,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 24,
          fontWeight: FontWeight.w700,
        ),
        onChanged: onChanged,
        decoration: InputDecoration(
          contentPadding: EdgeInsets.zero,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(height < 55 ? 9 : 12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(height < 55 ? 9 : 12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(height < 55 ? 9 : 12),
            borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
          ),
        ),
        onTap: () {
          if (controller.text.isNotEmpty) {
            controller.selection = TextSelection.collapsed(
              offset: controller.text.length,
            );
          }
        },
        onSubmitted: (_) {
          if (index < 5) focusNode.nextFocus();
        },
        onEditingComplete: () {
          if (index < 5) focusNode.nextFocus();
        },
      ),
    ),
  );
}

class _VerificationStatus extends StatelessWidget {
  const _VerificationStatus({
    required this.message,
    required this.isError,
    required this.isSuccess,
  });

  final String message;
  final bool isError;
  final bool isSuccess;

  @override
  Widget build(BuildContext context) {
    final foreground = isError
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
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('verify-status'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          message,
          style: TextStyle(color: foreground, fontSize: 13, height: 1.5),
        ),
      ),
    );
  }
}
