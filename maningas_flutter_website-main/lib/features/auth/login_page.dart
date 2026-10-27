import 'package:flutter/material.dart';

import '../../core/network/api_failure.dart';
import 'application/patient_auth_controller.dart';
import 'application/patient_auth_scope.dart';
import 'application/patient_auth_setup.dart';
import 'forgot_password_page.dart';
import 'registration_page.dart';
import 'verify_email_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({this.controller, this.initialMessage, super.key});

  final PatientAuthController? controller;
  final String? initialMessage;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showPassword = false;
  bool _rememberMe = false;
  bool _hasSubmitted = false;
  String? _feedbackMessage;
  bool _feedbackIsError = false;
  PatientAuthController? _controller;
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    _feedbackMessage = widget.initialMessage;
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    if (_ownsController) _controller?.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final inheritedController = PatientAuthScope.maybeOf(context);
    _controller = widget.controller ?? inheritedController;
    if (_controller == null) {
      _controller = createPatientAuthController();
      _ownsController = true;
    }
    _controller!.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _submitLogin() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _hasSubmitted = true;
      _feedbackMessage = null;
      _feedbackIsError = false;
    });
    if (!_formKey.currentState!.validate()) return;

    try {
      final result = await _controller!.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        rememberMe: _rememberMe,
      );
      if (!mounted) return;
      if (result.requiresEmailVerification) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => VerifyEmailPage(email: result.email),
          ),
        );
        return;
      }
      setState(() {
        _feedbackMessage = 'Sign-in successful.';
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _feedbackMessage = failure.message;
        _feedbackIsError = true;
      });
    }
  }

  void _openForgotPassword() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ForgotPasswordPage()));
  }

  void _openRegistration() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const RegistrationPage()));
  }

  void _showUnavailableDestination(String destination) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.info_outline),
        title: Text(destination),
        content: const Text(
          'This destination is not available in the patient portal yet.',
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final mobile = width <= 760;
        final smallPhone = width <= 420;
        final tablet = width <= 1050;
        final formPanel = _LoginFormPanel(
          mobile: mobile,
          smallPhone: smallPhone,
          tablet: tablet,
          viewportWidth: width,
          minimumHeight: constraints.maxHeight,
          formKey: _formKey,
          emailController: _emailController,
          passwordController: _passwordController,
          showPassword: _showPassword,
          rememberMe: _rememberMe,
          hasSubmitted: _hasSubmitted,
          feedbackMessage: _feedbackMessage,
          feedbackIsError: _feedbackIsError,
          isLoading: _controller?.isLoading ?? false,
          onTogglePassword: () =>
              setState(() => _showPassword = !_showPassword),
          onRememberChanged: (value) => setState(() => _rememberMe = value),
          onChanged: () {
            if (_feedbackMessage != null) {
              setState(() {
                _feedbackMessage = null;
                _feedbackIsError = false;
              });
            }
          },
          onSubmit: _submitLogin,
          onForgotPassword: _openForgotPassword,
          onCreateAccount: _openRegistration,
          onFooterLink: _showUnavailableDestination,
        );

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: mobile
              ? SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: formPanel,
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: tablet ? 3 : 9,
                      child: _BrandPanel(
                        padding: tablet ? 40 : 60,
                        titleSize: tablet ? 36 : 50,
                      ),
                    ),
                    Expanded(flex: tablet ? 5 : 11, child: formPanel),
                  ],
                ),
        );
      },
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({required this.padding, required this.titleSize});

  final double padding;
  final double titleSize;

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
                  colors: [
                    Color(0xFF1D4ED8),
                    Color(0xFF2563EB),
                    Color(0xFF3B82F6),
                  ],
                  stops: [0, 0.48, 1],
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.7, -0.6),
                  radius: 1.1,
                  colors: [Color(0x40DBEAFE), Color(0x003B82F6)],
                ),
              ),
            ),
          ),
          Positioned(
            width: 520,
            height: 520,
            top: -240,
            right: -220,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x21FFFFFF)),
              ),
            ),
          ),
          Positioned(
            width: 420,
            height: 420,
            left: -210,
            bottom: -230,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x1ADBEAFE),
                border: Border.all(color: const Color(0x14FFFFFF)),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _BrandMark(),
                    const SizedBox(height: 28),
                    Text(
                      'Gonzales Vision Clinic',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: titleSize,
                        height: 1.04,
                        letterSpacing: -2.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Your vision care, appointments, and patient '
                      'information all in one place.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 15,
                        height: 1.75,
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

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dimension = compact ? 38.0 : 74.0;
    return Container(
      width: dimension,
      height: dimension,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: compact ? const Color(0xFF2563EB) : const Color(0x21FFFFFF),
        borderRadius: BorderRadius.circular(compact ? 10 : 18),
        border: compact ? null : Border.all(color: const Color(0x38FFFFFF)),
        boxShadow: compact
            ? const [BoxShadow(color: Color(0x2E2563EB), blurRadius: 14)]
            : null,
      ),
      child: Text(
        'G',
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 21 : 34,
          height: 1,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _LoginFormPanel extends StatelessWidget {
  const _LoginFormPanel({
    required this.mobile,
    required this.smallPhone,
    required this.tablet,
    required this.viewportWidth,
    required this.minimumHeight,
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.showPassword,
    required this.rememberMe,
    required this.hasSubmitted,
    required this.feedbackMessage,
    required this.feedbackIsError,
    required this.isLoading,
    required this.onTogglePassword,
    required this.onRememberChanged,
    required this.onChanged,
    required this.onSubmit,
    required this.onForgotPassword,
    required this.onCreateAccount,
    required this.onFooterLink,
  });

  final bool mobile;
  final bool smallPhone;
  final bool tablet;
  final double viewportWidth;
  final double minimumHeight;
  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool showPassword;
  final bool rememberMe;
  final bool hasSubmitted;
  final String? feedbackMessage;
  final bool feedbackIsError;
  final bool isLoading;
  final VoidCallback onTogglePassword;
  final ValueChanged<bool> onRememberChanged;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;
  final VoidCallback onCreateAccount;
  final ValueChanged<String> onFooterLink;

  @override
  Widget build(BuildContext context) {
    final panelPadding = mobile
        ? EdgeInsets.fromLTRB(
            smallPhone ? 10 : 16,
            smallPhone ? 14 : 22,
            smallPhone ? 10 : 16,
            smallPhone ? 15 : 20,
          )
        : EdgeInsets.fromLTRB(tablet ? 40 : 70, 48, tablet ? 40 : 70, 28);
    final cardPadding = mobile
        ? EdgeInsets.all(smallPhone ? 16 : 20)
        : EdgeInsets.all(tablet ? 36 : 44);

    final card = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: _LoginCard(
          mobile: mobile,
          smallPhone: smallPhone,
          viewportWidth: viewportWidth,
          cardPadding: cardPadding,
          formKey: formKey,
          emailController: emailController,
          passwordController: passwordController,
          showPassword: showPassword,
          rememberMe: rememberMe,
          hasSubmitted: hasSubmitted,
          feedbackMessage: feedbackMessage,
          feedbackIsError: feedbackIsError,
          isLoading: isLoading,
          onTogglePassword: onTogglePassword,
          onRememberChanged: onRememberChanged,
          onChanged: onChanged,
          onSubmit: onSubmit,
          onForgotPassword: onForgotPassword,
          onCreateAccount: onCreateAccount,
        ),
      ),
    );
    final footer = _LoginFooter(onPressed: onFooterLink);
    final desktopContent = SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: (minimumHeight - panelPadding.vertical).clamp(
            0.0,
            double.infinity,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [card, const SizedBox(height: 25), footer],
        ),
      ),
    );

    return Container(
      padding: panelPadding,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0xFFF8FBFF)],
        ),
      ),
      child: mobile
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                card,
                Padding(padding: const EdgeInsets.only(top: 18), child: footer),
              ],
            )
          : desktopContent,
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.mobile,
    required this.smallPhone,
    required this.viewportWidth,
    required this.cardPadding,
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.showPassword,
    required this.rememberMe,
    required this.hasSubmitted,
    required this.feedbackMessage,
    required this.feedbackIsError,
    required this.isLoading,
    required this.onTogglePassword,
    required this.onRememberChanged,
    required this.onChanged,
    required this.onSubmit,
    required this.onForgotPassword,
    required this.onCreateAccount,
  });

  final bool mobile;
  final bool smallPhone;
  final double viewportWidth;
  final EdgeInsets cardPadding;
  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool showPassword;
  final bool rememberMe;
  final bool hasSubmitted;
  final String? feedbackMessage;
  final bool feedbackIsError;
  final bool isLoading;
  final VoidCallback onTogglePassword;
  final ValueChanged<bool> onRememberChanged;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;
  final VoidCallback onCreateAccount;

  @override
  Widget build(BuildContext context) {
    final headingFontSize = smallPhone
        ? 25.6
        : mobile
        ? 28.8
        : (viewportWidth * 0.03).clamp(30.4, 37.6).toDouble();
    final subtitleFontSize = smallPhone
        ? 12.48
        : mobile
        ? 13.12
        : 14.0;

    return Container(
      key: const ValueKey('login-card'),
      width: double.infinity,
      padding: cardPadding,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(
          smallPhone
              ? 12
              : mobile
              ? 14
              : 18,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.08),
            blurRadius: mobile ? 40 : 25,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mobile) ...[
            Row(
              children: [
                const _BrandMark(compact: true),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'Gonzales Vision Clinic',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: smallPhone ? 21 : 25),
          ],
          const Text(
            'PATIENT PORTAL',
            style: TextStyle(
              color: Color(0xFF2563EB),
              fontSize: 10.9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Welcome back',
            style: TextStyle(
              color: const Color(0xFF0F172A),
              fontFamily: 'Segoe UI Black',
              fontFamilyFallback: const ['Segoe UI', 'Inter', 'sans-serif'],
              fontSize: headingFontSize,
              height: 1.08,
              letterSpacing: -headingFontSize * 0.045,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            'Sign in to access your patient account.',
            style: TextStyle(
              color: const Color(0xFF475569),
              fontFamily: 'Inter',
              fontFamilyFallback: const [
                'ui-sans-serif',
                'system-ui',
                '-apple-system',
                'BlinkMacSystemFont',
                'Segoe UI',
                'sans-serif',
              ],
              fontSize: subtitleFontSize,
              height: mobile ? 1.7 : 1.6,
              fontWeight: FontWeight.w400,
            ),
          ),
          SizedBox(height: mobile ? 25 : 30),
          Form(
            key: formKey,
            autovalidateMode: hasSubmitted
                ? AutovalidateMode.onUserInteraction
                : AutovalidateMode.disabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LoginField(
                  label: 'Email Address',
                  placeholder: 'Enter your email address',
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: _validateEmail,
                  onChanged: (_) => onChanged(),
                ),
                const SizedBox(height: 19),
                _LoginField(
                  label: 'Password',
                  placeholder: 'Enter your password',
                  controller: passwordController,
                  obscureText: !showPassword,
                  textInputAction: TextInputAction.done,
                  validator: (value) => (value ?? '').isEmpty
                      ? 'Please enter your password.'
                      : null,
                  onChanged: (_) => onChanged(),
                  suffix: IconButton(
                    tooltip: showPassword ? 'Hide password' : 'Show password',
                    onPressed: onTogglePassword,
                    icon: Icon(
                      showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 19,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    InkWell(
                      onTap: () => onRememberChanged(!rememberMe),
                      borderRadius: BorderRadius.circular(4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            key: const ValueKey('remember-me'),
                            value: rememberMe,
                            onChanged: (value) =>
                                onRememberChanged(value ?? false),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 3),
                          const Text(
                            'Remember me',
                            style: TextStyle(
                              color: Color(0xFF475569),
                              fontSize: 11.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: onForgotPassword,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF2563EB),
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Forgot password?',
                        style: TextStyle(
                          fontSize: 11.8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (feedbackMessage case final message?) ...[
                  const SizedBox(height: 8),
                  Container(
                    key: const ValueKey('login-feedback-message'),
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: feedbackIsError
                          ? const Color(0xFFFEF2F2)
                          : const Color(0xFFEFF6FF),
                      border: Border.all(
                        color: feedbackIsError
                            ? const Color(0xFFFECACA)
                            : const Color(0xFFBFDBFE),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      message,
                      style: TextStyle(
                        color: feedbackIsError
                            ? const Color(0xFFB91C1C)
                            : const Color(0xFF1D4ED8),
                        fontSize: 11.8,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  height: 46,
                  child: FilledButton(
                    key: const ValueKey('login-submit'),
                    onPressed: isLoading ? null : onSubmit,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isLoading) ...[
                          const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 9),
                          const Text('Signing in...'),
                        ] else ...[
                          const Text(
                            'Sign In',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 9),
                          const Icon(Icons.arrow_forward, size: 17),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 23),
          LayoutBuilder(
            builder: (context, constraints) {
              final dividerLabel = Text(
                'New to the Patient Portal?',
                style: TextStyle(
                  color: const Color(0xFF94A3B8),
                  fontSize: smallPhone ? 10 : 10.9,
                ),
              );
              if (constraints.maxWidth < 300) {
                return Center(child: dividerLabel);
              }
              return Row(
                children: [
                  const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    child: dividerLabel,
                  ),
                  const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 46,
            child: OutlinedButton(
              onPressed: onCreateAccount,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2563EB),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              child: const Text(
                'Create Patient Account',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 25),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: 14, color: Color(0xFF94A3B8)),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Your account information is protected and kept confidential.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 10.5,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String? _validateEmail(String? value) {
  final email = (value ?? '').trim();
  if (email.isEmpty) return 'Please enter your email address.';
  if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(email)) {
    return 'Please enter a valid email address.';
  }
  return null;
}

class _LoginField extends StatelessWidget {
  const _LoginField({
    required this.label,
    required this.placeholder,
    required this.controller,
    required this.validator,
    required this.onChanged,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.suffix,
  });

  final String label;
  final String placeholder;
  final TextEditingController controller;
  final String? Function(String?) validator;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        FormField<String>(
          validator: validator,
          builder: (fieldState) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 46,
                child: TextField(
                  key: ValueKey('login-$label'),
                  controller: controller,
                  keyboardType: keyboardType,
                  textInputAction: textInputAction,
                  obscureText: obscureText,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 14,
                  ),
                  onChanged: (value) {
                    fieldState.didChange(value);
                    onChanged(value);
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: placeholder,
                    hintStyle: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 14,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 0,
                    ),
                    suffixIcon: suffix ?? const SizedBox(width: 44),
                    suffixIconConstraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 46,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: const BorderSide(color: Color(0xFF93C5FD)),
                    ),
                  ),
                ),
              ),
              if (fieldState.errorText case final errorText?) ...[
                const SizedBox(height: 5),
                Text(
                  errorText,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 10.7,
                    height: 1.25,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LoginFooter extends StatelessWidget {
  const _LoginFooter({required this.onPressed});

  final ValueChanged<String> onPressed;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 9,
      runSpacing: 3,
      children: [
        const Text(
          '© 2026 Gonzales Vision Clinic',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
        ),
        const Text('•', style: TextStyle(color: Color(0xFFCBD5E1))),
        _FooterLink(
          label: 'Privacy Policy',
          onPressed: () => onPressed('Privacy Policy'),
        ),
        const Text('•', style: TextStyle(color: Color(0xFFCBD5E1))),
        _FooterLink(
          label: 'Terms & Conditions',
          onPressed: () => onPressed('Terms & Conditions'),
        ),
      ],
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF94A3B8),
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 20),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 10),
      ),
      child: Text(label),
    );
  }
}
