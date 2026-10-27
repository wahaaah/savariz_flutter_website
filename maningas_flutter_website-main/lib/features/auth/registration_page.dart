import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../../core/network/api_failure.dart';
import 'data/philippine_address_catalog.dart';
import 'application/patient_auth_controller.dart';
import 'application/patient_auth_scope.dart';
import 'application/patient_auth_setup.dart';
import 'domain/patient_registration.dart';
import 'login_page.dart';
import 'verify_email_page.dart';

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  static const int _minimumAge = 10;
  static const int _maximumAge = 99;

  final _pageScrollController = ScrollController();
  final _controllers = <String, TextEditingController>{
    for (final field in _textFields) field.id: TextEditingController(),
  };
  final _focusNodes = <String, FocusNode>{
    for (final field in _textFields) field.id: FocusNode(),
  };

  bool _submitted = false;
  bool _termsAccepted = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  bool _isSubmitting = false;
  bool _statusIsError = false;
  PatientAuthController? _authController;
  bool _ownsController = false;
  String? _status;
  String? _firstError;
  String? _gender;
  String? _province;
  String? _city;
  String? _barangay;
  Map<String, String> _errors = {};
  int? _age;
  PhilippineAddressCatalog? _addressCatalog;
  String? _addressDataError;
  bool _isLoadingAddressData = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAddressCatalog());
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
    if (_ownsController) _authController?.dispose();
    _pageScrollController.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focus in _focusNodes.values) {
      focus.dispose();
    }
    super.dispose();
  }

  String _value(String id) => _controllers[id]!.text;

  void _handleInputChanged(String id, String value) {
    setState(() {
      if (id == 'dateOfBirth') {
        _age = _calculateAge(value);
        _controllers['age']!.text = _age?.toString() ?? '';
      }
      _errors.remove(id);
      _status = null;
      _firstError = null;
    });
  }

  int? _calculateAge(String value) {
    final date = _parseIsoDate(value);
    if (date == null) return null;
    final today = DateTime.now();
    var years = today.year - date.year;
    if (today.month < date.month ||
        (today.month == date.month && today.day < date.day)) {
      years--;
    }
    return years;
  }

  Future<void> _pickDateOfBirth() async {
    FocusScope.of(context).unfocus();
    final today = DateUtils.dateOnly(DateTime.now());
    final earliestBirthDate = _yearsAgo(today, _maximumAge);
    final latestBirthDate = _yearsAgo(today, _minimumAge);
    final existingDate = _parseIsoDate(_value('dateOfBirth'));
    final defaultInitialDate = latestBirthDate;
    final existingDateOnly = existingDate == null
        ? null
        : DateUtils.dateOnly(existingDate);
    final initialDate =
        existingDateOnly != null &&
            !existingDateOnly.isBefore(earliestBirthDate) &&
            !existingDateOnly.isAfter(latestBirthDate)
        ? existingDateOnly
        : defaultInitialDate.isBefore(earliestBirthDate)
        ? earliestBirthDate
        : defaultInitialDate.isAfter(latestBirthDate)
        ? latestBirthDate
        : defaultInitialDate;
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: earliestBirthDate,
      lastDate: latestBirthDate,
      helpText: 'Select your date of birth',
      builder: (context, child) =>
          Theme(data: Theme.of(context), child: child!),
    );
    if (selectedDate == null || !mounted) return;

    final formattedDate =
        '${selectedDate.year.toString().padLeft(4, '0')}-'
        '${selectedDate.month.toString().padLeft(2, '0')}-'
        '${selectedDate.day.toString().padLeft(2, '0')}';
    _controllers['dateOfBirth']!.text = formattedDate;
    _handleInputChanged('dateOfBirth', formattedDate);
  }

  DateTime? _parseIsoDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value.trim());
    if (match == null) return null;
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  DateTime _yearsAgo(DateTime date, int years) {
    final year = date.year - years;
    final lastDayOfMonth = DateTime(year, date.month + 1, 0).day;
    return DateTime(
      year,
      date.month,
      date.day > lastDayOfMonth ? lastDayOfMonth : date.day,
    );
  }

  Future<void> _loadAddressCatalog() async {
    try {
      final catalog = await PhilippineAddressCatalog.load();
      if (!mounted) return;
      setState(() {
        _addressCatalog = catalog;
        _isLoadingAddressData = false;
        _addressDataError = null;
      });
    } on Exception catch (error, stackTrace) {
      if (!mounted) return;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError(
            'Unable to load Philippine address data (${error.runtimeType}).',
          ),
          stack: stackTrace,
          library: 'patient registration',
        ),
      );
      setState(() {
        _isLoadingAddressData = false;
        _addressDataError =
            'Philippine address choices could not be loaded. Please retry.';
      });
    }
  }

  void _retryAddressCatalog() {
    setState(() {
      _isLoadingAddressData = true;
      _addressDataError = null;
    });
    unawaited(_loadAddressCatalog());
  }

  Map<String, String> _validate() {
    final errors = <String, String>{};
    void requiredText(String id, String label, {int minLength = 1}) {
      final text = _value(id).trim();
      if (text.isEmpty) {
        errors[id] = 'Please enter $label.';
      } else if (text.length < minLength) {
        errors[id] = 'Please enter a valid $label.';
      }
    }

    requiredText('firstName', 'your first name', minLength: 2);
    final middleName = _value('middleName').trim();
    if (middleName.isNotEmpty && middleName.length < 2) {
      errors['middleName'] =
          'Please enter a valid middle name or leave it blank.';
    }
    requiredText('lastName', 'your last name', minLength: 2);

    final dobValue = _value('dateOfBirth').trim();
    final dob = _parseIsoDate(dobValue);
    final today = DateUtils.dateOnly(DateTime.now());
    final earliestBirthDate = _yearsAgo(today, _maximumAge);
    final latestBirthDate = _yearsAgo(today, _minimumAge);
    if (dobValue.isEmpty) {
      errors['dateOfBirth'] = 'Please select your date of birth.';
    } else if (dob == null) {
      errors['dateOfBirth'] = 'Please enter a valid date of birth.';
    } else if (DateUtils.dateOnly(dob).isAfter(today)) {
      errors['dateOfBirth'] = 'Date of birth cannot be in the future.';
    } else if (DateUtils.dateOnly(dob).isBefore(earliestBirthDate) ||
        DateUtils.dateOnly(dob).isAfter(latestBirthDate)) {
      errors['dateOfBirth'] =
          'You must be between $_minimumAge and $_maximumAge years old.';
    } else {
      _age = _calculateAge(dobValue);
    }

    if (_gender == null) {
      errors['gender'] = 'Please select your gender.';
    }
    requiredText('contact', 'your contact number');
    final contact = _value('contact').trim();
    if (contact.isNotEmpty &&
        !RegExp(r'^(\+63|0)9\d{9}$')
            .hasMatch(contact.replaceAll(RegExp(r'[\s-]'), ''))) {
      errors['contact'] = 'Please enter a valid Philippine mobile number.';
    }

    requiredText('addressUnit', 'your house, unit, lot, or block');
    requiredText('addressStreet', 'your street');
    if (_addressCatalog?.provinceByCode(_province) == null) {
      errors['addressProvince'] = 'Please select your province.';
    }
    if (_addressCatalog?.municipalityByCode(_city) == null ||
        _addressCatalog?.municipalityByCode(_city)?.parentCode != _province) {
      errors['addressCityMunicipality'] =
          'Please select your city or municipality.';
    }
    if (_addressCatalog?.barangayById(_barangay)?.parentCode != _city) {
      errors['addressBarangay'] = 'Please select your barangay.';
    }
    requiredText('addressZipCode', 'your ZIP code');
    final zip = _value('addressZipCode').trim();
    if (zip.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(zip)) {
      errors['addressZipCode'] = 'ZIP code must be exactly 4 digits.';
    }

    final email = _value('email').trim();
    if (email.isEmpty) {
      errors['email'] = 'Please enter your email address.';
    } else if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      errors['email'] = 'Please enter a valid email address.';
    }

    final password = _value('password');
    if (password.isEmpty) {
      errors['password'] = 'Please create a password.';
    } else if (password.length < 8) {
      errors['password'] = 'Password must contain at least 8 characters.';
    }
    final confirmPassword = _value('confirmPassword');
    if (confirmPassword.isEmpty) {
      errors['confirmPassword'] = 'Please confirm your password.';
    } else if (confirmPassword != password) {
      errors['confirmPassword'] = 'Passwords do not match.';
    }
    if (!_termsAccepted) {
      errors['terms'] = 'You must agree to the Terms and Conditions.';
    }
    return errors;
  }

  Future<void> _submitRegistration() async {
    FocusScope.of(context).unfocus();
    if (_addressCatalog == null) {
      setState(() {
        _status =
            _addressDataError ??
            'Wait for Philippine address choices to finish loading.';
        _statusIsError = true;
      });
      return;
    }
    final errors = _validate();
    if (errors.isNotEmpty) {
      setState(() {
        _submitted = true;
        _errors = errors;
        _status = null;
        _firstError = errors.keys.first;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final focus = _focusNodes[_firstError];
        if (focus != null) {
          focus.requestFocus();
        } else {
          _pageScrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errors = {};
      _status = null;
      _statusIsError = false;
    });
    try {
      final result = await _authController!.register(
        PatientRegistrationRequest(
          name: [
            _value('firstName').trim(),
            _value('middleName').trim(),
            _value('lastName').trim(),
          ].where((part) => part.isNotEmpty).join(' '),
          age: _age!,
          dateOfBirth: _value('dateOfBirth').trim(),
          gender: _gender ?? '',
          contact: _value('contact').trim(),
          email: _value('email').trim().toLowerCase(),
          password: _value('password'),
          addressUnit: _value('addressUnit').trim(),
          addressStreet: _value('addressStreet').trim(),
          addressBarangay: _addressCatalog!.barangayById(_barangay)!.name,
          addressCityMunicipality: _addressCatalog!
              .municipalityByCode(_city)!
              .code!,
          addressProvince: _addressCatalog!.provinceByCode(_province)!.code!,
          addressZipCode: _value('addressZipCode').trim(),
        ),
      );
      if (!mounted) return;
      if (!result.requiresEmailVerification) {
        setState(() {
          _isSubmitting = false;
          _status = 'The clinic service did not request email verification.';
          _statusIsError = true;
        });
        return;
      }
      setState(() => _isSubmitting = false);
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => VerifyEmailPage(email: result.email),
        ),
      );
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _status = failure.message;
        _statusIsError = true;
      });
    } finally {
      if (mounted && _isSubmitting) {
        setState(() => _isSubmitting = false);
      }
    }
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

  void _showTerms() {
    showDialog<void>(
      context: context,
      builder: (context) => const _TermsDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PatientPortalTheme.light,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final tablet = width <= 850;
          final phone = width <= 600;
          final content = _RegistrationFormPanel(
            tablet: tablet,
            phone: phone,
            isSubmitting: _isSubmitting,
            status: _status,
            statusIsError: _statusIsError,
            errors: _errors,
            age: _age,
            submitted: _submitted,
            termsAccepted: _termsAccepted,
            showPassword: _showPassword,
            showConfirmPassword: _showConfirmPassword,
            gender: _gender,
            province: _province,
            city: _city,
            barangay: _barangay,
            provinces: _addressCatalog?.provinces ?? const [],
            citiesMunicipalities: _province == null
                ? const []
                : _addressCatalog?.municipalitiesFor(_province!) ?? const [],
            barangays: _city == null
                ? const []
                : _addressCatalog?.barangaysFor(_city!) ?? const [],
            addressDataReady: _addressCatalog != null,
            addressDataLoading: _isLoadingAddressData,
            addressDataError: _addressDataError,
            onRetryAddressData: _retryAddressCatalog,
            controllers: _controllers,
            focusNodes: _focusNodes,
            onInputChanged: _handleInputChanged,
            onPickDateOfBirth: _pickDateOfBirth,
            onGenderChanged: (value) => setState(() {
              _gender = value;
              _errors.remove('gender');
            }),
            onProvinceChanged: (value) => setState(() {
              _province = value;
              _city = null;
              _barangay = null;
              _errors.remove('addressProvince');
              _errors.remove('addressCityMunicipality');
              _errors.remove('addressBarangay');
            }),
            onCityChanged: (value) => setState(() {
              _city = value;
              _barangay = null;
              _errors.remove('addressCityMunicipality');
              _errors.remove('addressBarangay');
            }),
            onBarangayChanged: (value) => setState(() {
              _barangay = value;
              _errors.remove('addressBarangay');
            }),
            onTermsChanged: (value) => setState(() {
              _termsAccepted = value;
              _errors.remove('terms');
            }),
            onTogglePassword: () =>
                setState(() => _showPassword = !_showPassword),
            onToggleConfirmPassword: () =>
                setState(() => _showConfirmPassword = !_showConfirmPassword),
            onSubmit: _submitRegistration,
            onShowLogin: _backToLogin,
            onShowTerms: _showTerms,
          );

          final body = tablet
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _BrandPanel(tablet: tablet, phone: phone),
                    content,
                  ],
                )
              : IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 2,
                        child: _BrandPanel(tablet: tablet, phone: phone),
                      ),
                      Expanded(flex: 3, child: content),
                    ],
                  ),
                );

          return Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            body: SingleChildScrollView(
              controller: _pageScrollController,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: Container(
                    margin: EdgeInsets.symmetric(
                      horizontal: phone ? 15 : 20,
                      vertical: phone ? 15 : 40,
                    ),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(phone ? 18 : 24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1F0F172A),
                          blurRadius: 70,
                          offset: Offset(0, 18),
                        ),
                      ],
                    ),
                    child: body,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({required this.tablet, required this.phone});

  final bool tablet;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(
        phone
            ? 24
            : tablet
            ? 30
            : 42,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2563EB), Color(0xFF1D4ED8), Color(0xFF1E40AF)],
          stops: [0, 0.55, 1],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned(
            top: -100,
            right: -90,
            child: _DecorationCircle(size: 280, opacity: 0.08),
          ),
          const Positioned(
            bottom: -100,
            left: -70,
            child: _DecorationCircle(size: 220, opacity: 0.07),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: phone ? 58 : 72,
                height: phone ? 58 : 72,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(phone ? 15 : 18),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 30,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: const _ClinicLogoFallback(),
              ),
              SizedBox(
                height: phone
                    ? 18
                    : tablet
                    ? 22
                    : 30,
              ),
              Text(
                'Your Eye Care,\nAll in One Place.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: phone
                      ? 27
                      : tablet
                      ? 31
                      : 44,
                  height: 1.08,
                  letterSpacing: -1.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: phone ? 10 : 14),
              Text(
                'Create your Gonzales Vision Clinic patient account to manage '
                'your appointments and stay connected with your eye care services.',
                style: TextStyle(
                  color: const Color(0xD1FFFFFF),
                  fontSize: phone ? 13 : 15,
                  height: 1.7,
                ),
              ),
              SizedBox(height: phone ? 22 : 34),
              if (tablet && !phone)
                const Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    _BrandFeature('Secure patient account'),
                    _BrandFeature('Easy appointment access'),
                    _BrandFeature('Email verification'),
                  ],
                )
              else
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BrandFeature('Secure patient account'),
                    SizedBox(height: 13),
                    _BrandFeature('Easy appointment access'),
                    SizedBox(height: 13),
                    _BrandFeature('Email verification'),
                  ],
                ),
              if (!tablet) ...[
                const SizedBox(height: 40),
                const Text(
                  '© 2026 Gonzales Vision Clinic',
                  style: TextStyle(color: Color(0x94FFFFFF), fontSize: 12),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ClinicLogoFallback extends StatelessWidget {
  const _ClinicLogoFallback();

  @override
  Widget build(BuildContext context) => const Center(
    child: Text(
      'G',
      style: TextStyle(
        color: Color(0xFF2563EB),
        fontSize: 40,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _DecorationCircle extends StatelessWidget {
  const _DecorationCircle({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: opacity),
      shape: BoxShape.circle,
    ),
  );
}

class _BrandFeature extends StatelessWidget {
  const _BrandFeature(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.13),
          shape: BoxShape.circle,
        ),
        child: const Text(
          '✓',
          style: TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
      const SizedBox(width: 11),
      Flexible(
        child: Text(
          label,
          style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 14),
        ),
      ),
    ],
  );
}

class _RegistrationFormPanel extends StatelessWidget {
  const _RegistrationFormPanel({
    required this.tablet,
    required this.phone,
    required this.isSubmitting,
    required this.status,
    required this.statusIsError,
    required this.errors,
    required this.age,
    required this.submitted,
    required this.termsAccepted,
    required this.showPassword,
    required this.showConfirmPassword,
    required this.gender,
    required this.province,
    required this.city,
    required this.barangay,
    required this.provinces,
    required this.citiesMunicipalities,
    required this.barangays,
    required this.addressDataReady,
    required this.addressDataLoading,
    required this.addressDataError,
    required this.onRetryAddressData,
    required this.controllers,
    required this.focusNodes,
    required this.onInputChanged,
    required this.onPickDateOfBirth,
    required this.onGenderChanged,
    required this.onProvinceChanged,
    required this.onCityChanged,
    required this.onBarangayChanged,
    required this.onTermsChanged,
    required this.onTogglePassword,
    required this.onToggleConfirmPassword,
    required this.onSubmit,
    required this.onShowLogin,
    required this.onShowTerms,
  });

  final bool tablet;
  final bool phone;
  final bool isSubmitting;
  final String? status;
  final bool statusIsError;
  final Map<String, String> errors;
  final int? age;
  final bool submitted;
  final bool termsAccepted;
  final bool showPassword;
  final bool showConfirmPassword;
  final String? gender;
  final String? province;
  final String? city;
  final String? barangay;
  final List<PhilippineAddressOption> provinces;
  final List<PhilippineAddressOption> citiesMunicipalities;
  final List<PhilippineAddressOption> barangays;
  final bool addressDataReady;
  final bool addressDataLoading;
  final String? addressDataError;
  final VoidCallback onRetryAddressData;
  final Map<String, TextEditingController> controllers;
  final Map<String, FocusNode> focusNodes;
  final void Function(String id, String value) onInputChanged;
  final VoidCallback onPickDateOfBirth;
  final ValueChanged<String?> onGenderChanged;
  final ValueChanged<String?> onProvinceChanged;
  final ValueChanged<String?> onCityChanged;
  final ValueChanged<String?> onBarangayChanged;
  final ValueChanged<bool> onTermsChanged;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirmPassword;
  final VoidCallback onSubmit;
  final VoidCallback onShowLogin;
  final VoidCallback onShowTerms;

  TextEditingController _controller(String id) => controllers[id]!;

  List<String>? _autofillHint(String? autocomplete) {
    switch (autocomplete) {
      case 'given-name':
        return const [AutofillHints.givenName];
      case 'family-name':
        return const [AutofillHints.familyName];
      case 'tel':
        return const [AutofillHints.telephoneNumber];
      case 'email':
        return const [AutofillHints.email];
      case 'new-password':
        return const [AutofillHints.newPassword];
      default:
        return null;
    }
  }

  Widget _textField(
    String id, {
    required String label,
    required String hint,
    String? help,
    TextInputType? keyboardType,
    String? autocomplete,
    int? maxLength,
    bool readOnly = false,
    bool obscure = false,
    Widget? suffix,
    VoidCallback? onTap,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return _FormFieldBlock(
      label: label,
      error: errors[id],
      help: help,
      child: SizedBox(
        height: 46,
        child: TextField(
          key: ValueKey('registration-$id'),
          controller: _controller(id),
          focusNode: focusNodes[id],
          keyboardType: keyboardType,
          obscureText: obscure,
          readOnly: readOnly,
          onTap: onTap,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          autofillHints: _autofillHint(autocomplete),
          onChanged: (value) => onInputChanged(id, value),
          style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14),
          decoration: _decoration(hint, suffix: suffix),
        ),
      ),
    );
  }

  Widget _selectField({
    required String id,
    required String label,
    required String? value,
    required List<String> options,
    required String hint,
    required ValueChanged<String?> onChanged,
    String? help,
    bool disabled = false,
  }) {
    return _FormFieldBlock(
      label: label,
      error: errors[id],
      help: help,
      child: SizedBox(
        height: 46,
        child: DropdownButtonFormField<String>(
          key: ValueKey('registration-$id'),
          initialValue: value,
          isExpanded: true,
          dropdownColor: Colors.white,
          focusColor: Colors.white,
          style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF64748B),
          ),
          decoration: _decoration(hint),
          items: options
              .map(
                (option) => DropdownMenuItem(
                  value: option,
                  child: Text(
                    option,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 14,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: disabled ? null : onChanged,
        ),
      ),
    );
  }

  Widget _addressSelectField({
    required String id,
    required String label,
    required String? value,
    required List<PhilippineAddressOption> options,
    required String hint,
    required ValueChanged<String?> onChanged,
    bool disabled = false,
  }) {
    return _FormFieldBlock(
      label: label,
      error: errors[id],
      child: SizedBox(
        height: 46,
        child: DropdownButtonFormField<String>(
          key: ValueKey('registration-$id'),
          initialValue: value,
          isExpanded: true,
          dropdownColor: Colors.white,
          focusColor: Colors.white,
          style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF64748B),
          ),
          decoration: _decoration(hint),
          items: options
              .map(
                (option) => DropdownMenuItem(
                  value: option.id,
                  child: Text(
                    option.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 14,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: disabled ? null : onChanged,
        ),
      ),
    );
  }

  Widget _row(List<Widget> children) => phone
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _withSpacing(children, 18),
        )
      : Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _withSpacing(
            children.map((child) => Expanded(child: child)).toList(),
            16,
            horizontal: true,
          ),
        );

  List<Widget> _withSpacing(
    List<Widget> children,
    double spacing, {
    bool horizontal = false,
  }) {
    final result = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) {
        result.add(
          horizontal ? SizedBox(width: spacing) : SizedBox(height: spacing),
        );
      }
      result.add(children[index]);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(
        phone
            ? 25
            : tablet
            ? 32
            : 42,
      ),
      child: _buildRegistrationForm(),
    );
  }

  Widget _buildRegistrationForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'PATIENT PORTAL',
          style: TextStyle(
            color: Color(0xFF2563EB),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          'Create your account',
          style: TextStyle(
            color: const Color(0xFF0F172A),
            fontSize: phone ? 27 : 31,
            height: 1.15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          'Create your patient account and verify your email to finish registration.',
          style: const TextStyle(
            color: Color(0xFF475569),
            fontSize: 14,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 28),
        if (!addressDataReady) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              border: Border.all(color: const Color(0xFFFDE68A)),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  addressDataError ??
                      (addressDataLoading
                          ? 'Loading Philippine address choices…'
                          : 'Philippine address choices are unavailable.'),
                  style: const TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 13,
                  ),
                ),
                if (!addressDataLoading && addressDataError != null)
                  TextButton(
                    onPressed: onRetryAddressData,
                    child: const Text('Retry loading addresses'),
                  ),
                if (addressDataLoading) ...[
                  const SizedBox(height: 9),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],
        _row([
          _textField(
            'firstName',
            label: 'First Name *',
            hint: 'First name',
            autocomplete: 'given-name',
            maxLength: 50,
          ),
          _textField(
            'middleName',
            label: 'Middle Name',
            hint: 'Middle name',
            autocomplete: 'additional-name',
            maxLength: 50,
          ),
        ]),
        const SizedBox(height: 18),
        _textField(
          'lastName',
          label: 'Last Name *',
          hint: 'Last name',
          autocomplete: 'family-name',
          maxLength: 50,
        ),
        const SizedBox(height: 18),
        _row([
          _textField(
            'dateOfBirth',
            label: 'Date of Birth *',
            hint: 'YYYY-MM-DD',
            readOnly: true,
            onTap: onPickDateOfBirth,
            suffix: IconButton(
              key: const ValueKey('registration-date-picker'),
              tooltip: 'Choose date of birth',
              onPressed: onPickDateOfBirth,
              icon: const Icon(
                Icons.calendar_today_outlined,
                color: Color(0xFF64748B),
                size: 18,
              ),
            ),
            help: errors['dateOfBirth'] == null
                ? null
                : 'Choose a date in YYYY-MM-DD format.',
          ),
          _textField(
            'age',
            label: 'Age',
            hint: 'Automatically calculated',
            help: 'Automatically calculated from your date of birth.',
            readOnly: true,
          ),
        ]),
        const SizedBox(height: 18),
        _selectField(
          id: 'gender',
          label: 'Gender *',
          value: gender,
          options: const ['Male', 'Female', 'Other'],
          hint: 'Select your gender',
          onChanged: onGenderChanged,
        ),
        const SizedBox(height: 18),
        _textField(
          'contact',
          label: 'Contact Number *',
          hint: '09XXXXXXXXX',
          help: 'Example: 09171234567',
          keyboardType: TextInputType.phone,
          autocomplete: 'tel',
          maxLength: 20,
        ),
        const SizedBox(height: 18),
        const _RequiredGroupLabel('Address *'),
        const SizedBox(height: 7),
        _row([
          _textField(
            'addressUnit',
            label: 'House / Unit / Lot / Block',
            hint: 'e.g. Blk 5 Lot 10',
            maxLength: 100,
          ),
          _textField(
            'addressStreet',
            label: 'Street',
            hint: 'e.g. Sampaguita Street',
            maxLength: 100,
          ),
        ]),
        const SizedBox(height: 12),
        _row([
          _addressSelectField(
            id: 'addressProvince',
            label: 'Province',
            value: province,
            options: provinces,
            hint: 'Select Province',
            onChanged: onProvinceChanged,
            disabled: !addressDataReady,
          ),
          _addressSelectField(
            id: 'addressCityMunicipality',
            label: 'City / Municipality',
            value: city,
            options: citiesMunicipalities,
            hint: province == null
                ? 'Select Province First'
                : 'Select City / Municipality',
            onChanged: onCityChanged,
            disabled: !addressDataReady || province == null,
          ),
        ]),
        const SizedBox(height: 12),
        _row([
          _addressSelectField(
            id: 'addressBarangay',
            label: 'Barangay',
            value: barangay,
            options: barangays,
            hint: city == null
                ? 'Select City / Municipality First'
                : 'Select Barangay',
            onChanged: onBarangayChanged,
            disabled: !addressDataReady || city == null,
          ),
          _textField(
            'addressZipCode',
            label: 'ZIP Code',
            hint: 'e.g. 3019',
            help: 'Enter your ZIP code.',
            keyboardType: TextInputType.number,
            maxLength: 10,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ]),
        const SizedBox(height: 18),
        _textField(
          'email',
          label: 'Email Address *',
          hint: 'you@example.com',
          help: 'Your verification code will be sent here.',
          keyboardType: TextInputType.emailAddress,
          autocomplete: 'email',
          maxLength: 190,
        ),
        const SizedBox(height: 18),
        _row([
          _textField(
            'password',
            label: 'Password *',
            hint: 'Create a password',
            obscure: !showPassword,
            maxLength: 100,
            autocomplete: 'new-password',
            suffix: _VisibilityToggle(
              visible: showPassword,
              onPressed: onTogglePassword,
              keyPrefix: 'registration-password',
            ),
          ),
          _textField(
            'confirmPassword',
            label: 'Confirm Password *',
            hint: 'Re-enter password',
            obscure: !showConfirmPassword,
            maxLength: 100,
            autocomplete: 'new-password',
            suffix: _VisibilityToggle(
              visible: showConfirmPassword,
              onPressed: onToggleConfirmPassword,
              keyPrefix: 'registration-confirm',
            ),
          ),
        ]),
        const SizedBox(height: 6),
        _PasswordStrength(password: controllers['password']!.text),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              key: const ValueKey('registration-terms-checkbox'),
              value: termsAccepted,
              onChanged: (value) => onTermsChanged(value ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              activeColor: const Color(0xFF2563EB),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Wrap(
                  children: [
                    const Text(
                      'I agree to the ',
                      style: TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 12,
                        height: 1.55,
                      ),
                    ),
                    InkWell(
                      key: const ValueKey('registration-terms-link'),
                      onTap: onShowTerms,
                      child: const Text(
                        'Terms and Conditions',
                        style: TextStyle(
                          color: Color(0xFF2563EB),
                          fontSize: 12,
                          height: 1.55,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Text(
                      ' of Gonzales Vision Clinic.',
                      style: TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 12,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (errors['terms'] != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 2),
            child: Text(
              errors['terms']!,
              key: const ValueKey('registration-error-terms'),
              style: _errorStyle,
            ),
          ),
        if (status != null) ...[
          const SizedBox(height: 12),
          _StatusBanner(message: status!, isError: statusIsError),
        ],
        const SizedBox(height: 18),
        SizedBox(
          height: 48,
          child: FilledButton(
            key: const ValueKey('registration-submit'),
            onPressed: isSubmitting || !addressDataReady ? null : onSubmit,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
              elevation: 0,
            ),
            child: isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Create Patient Account',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            children: [
              const Text(
                'Already have an account? ',
                style: TextStyle(color: Color(0xFF475569), fontSize: 13),
              ),
              InkWell(
                key: const ValueKey('registration-login-link'),
                onTap: onShowLogin,
                child: const Text(
                  'Sign in',
                  style: TextStyle(
                    color: Color(0xFF2563EB),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FormFieldBlock extends StatelessWidget {
  const _FormFieldBlock({
    required this.label,
    required this.child,
    this.error,
    this.help,
  });

  final String label;
  final Widget child;
  final String? error;
  final String? help;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 7),
      child,
      if (help != null) ...[
        const SizedBox(height: 4),
        Text(
          help!,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 11,
            height: 1.45,
          ),
        ),
      ],
      if (error != null) ...[
        const SizedBox(height: 4),
        Text(error!, style: _errorStyle),
      ],
    ],
  );
}

class _RequiredGroupLabel extends StatelessWidget {
  const _RequiredGroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Color(0xFF0F172A),
      fontSize: 13,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _VisibilityToggle extends StatelessWidget {
  const _VisibilityToggle({
    required this.visible,
    required this.onPressed,
    required this.keyPrefix,
  });

  final bool visible;
  final VoidCallback onPressed;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => IconButton(
    key: ValueKey('$keyPrefix-toggle'),
    tooltip: visible ? 'Hide password' : 'Show password',
    onPressed: onPressed,
    icon: Icon(
      visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      size: 18,
      color: const Color(0xFF94A3B8),
    ),
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 40, height: 40),
  );
}

class _PasswordStrength extends StatelessWidget {
  const _PasswordStrength({required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();
    var score = 0;
    if (password.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(password)) score++;
    if (RegExp(r'[0-9]').hasMatch(password)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;
    final label = const [
      '',
      'Weak password',
      'Fair password',
      'Good password',
      'Strong password',
    ][score];
    final color = score <= 1
        ? const Color(0xFFDC2626)
        : score == 2
        ? const Color(0xFFF59E0B)
        : const Color(0xFF16A34A);
    return Column(
      key: const ValueKey('password-strength'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: List.generate(
            4,
            (index) => Expanded(
              child: Container(
                key: ValueKey('strength-bar-$index'),
                height: 3,
                margin: EdgeInsets.only(right: index == 3 ? 0 : 4),
                decoration: BoxDecoration(
                  color: index < score ? color : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(label, style: TextStyle(color: color, fontSize: 10)),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('registration-status'),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: isError ? const Color(0xFFFEF2F2) : const Color(0xFFEFF6FF),
      border: Border.all(
        color: isError ? const Color(0xFFFECACA) : const Color(0xFFBFDBFE),
      ),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      message,
      style: TextStyle(
        color: isError ? const Color(0xFFB91C1C) : const Color(0xFF1D4ED8),
        fontSize: 13,
        height: 1.5,
      ),
    ),
  );
}

class _TermsDialog extends StatelessWidget {
  const _TermsDialog();

  static const _terms = [
    (
      '1. Patient Account',
      'By creating a patient account, you confirm that the information you '
          'provide is accurate and belongs to you.',
    ),
    (
      '2. Email Verification',
      'Your email address must be verified before your patient account can be '
          'used. A verification code will be sent to the email address you provide.',
    ),
    (
      '3. Personal Information',
      'The information submitted during registration may be used by Gonzales '
          'Vision Clinic to identify your patient record and provide clinic services.',
    ),
    (
      '4. Account Security',
      'You are responsible for keeping your password confidential. Do not share '
          'your account credentials with other people.',
    ),
    (
      '5. Accurate Information',
      'You agree to provide accurate and updated information when using the '
          'Patient Portal.',
    ),
    (
      '6. Clinic Services',
      'Patient Portal features may include appointment management, patient '
          'information, and other clinic services made available by Gonzales Vision Clinic.',
    ),
    (
      '7. Acceptance',
      'By checking the Terms and Conditions box and creating your account, you '
          'acknowledge that you have read and agreed to these terms.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 14, 18),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Terms and Conditions',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('terms-close'),
                    tooltip: 'Close Terms and Conditions',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            Flexible(
              child: SingleChildScrollView(
                key: const ValueKey('terms-scroll'),
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (heading, body) in _terms) ...[
                      Text(
                        heading,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        body,
                        style: const TextStyle(
                          color: Color(0xFF475569),
                          fontSize: 13,
                          height: 1.7,
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _decoration(String hint, {Widget? suffix}) => InputDecoration(
  hintText: hint,
  hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
  contentPadding: const EdgeInsets.symmetric(horizontal: 13),
  counterText: '',
  suffixIcon: suffix,
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
  errorBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: Color(0xFFDC2626)),
  ),
);

const _errorStyle = TextStyle(
  color: Color(0xFFDC2626),
  fontSize: 11,
  fontWeight: FontWeight.w600,
);

const _textFields = <_FieldDefinition>[
  _FieldDefinition('firstName'),
  _FieldDefinition('middleName'),
  _FieldDefinition('lastName'),
  _FieldDefinition('dateOfBirth'),
  _FieldDefinition('age'),
  _FieldDefinition('contact'),
  _FieldDefinition('addressUnit'),
  _FieldDefinition('addressStreet'),
  _FieldDefinition('addressZipCode'),
  _FieldDefinition('email'),
  _FieldDefinition('password'),
  _FieldDefinition('confirmPassword'),
];

class _FieldDefinition {
  const _FieldDefinition(this.id);

  final String id;
}
