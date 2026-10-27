import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/responsive.dart';
import '../../app/theme.dart';
import '../../core/network/api_failure.dart';
import '../auth/application/patient_auth_scope.dart';
import '../auth/data/philippine_address_catalog.dart';
import '../auth/domain/patient_session.dart';
import 'patient_profile_repository.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({this.initialDetails, this.initialName, super.key});

  final PatientProfileDetails? initialDetails;
  final String? initialName;

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;

  PatientProfileRepository? _profileRepository;
  PatientSession? _session;
  String? _loadError;
  bool _isLoadingProfile = false;
  bool _didLoadInitialDetails = false;
  int _loadGeneration = 0;
  String? _status;
  PhilippineAddressCatalog? _addressCatalog;
  String? _addressDataError;
  bool _isLoadingAddressData = true;
  String? _provinceId;
  String? _cityId;
  String? _barangayId;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final field in _fields)
        field.id: TextEditingController(text: _initialValue(field.id)),
    };
    final initialDetails = widget.initialDetails;
    if (initialDetails != null) {
      _applyDetails(initialDetails);
      _didLoadInitialDetails = true;
    }
    unawaited(_loadAddressCatalog());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _profileRepository = PatientAuthScope.patientProfileOf(context);
    _session = PatientAuthScope.maybeOf(context)?.currentSession;
    if (!_didLoadInitialDetails) _loadPatientDetails();
  }

  @override
  void dispose() {
    _loadGeneration++;
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAddressCatalog() async {
    try {
      final catalog = await PhilippineAddressCatalog.load();
      if (!mounted) return;
      setState(() {
        _addressCatalog = catalog;
        _isLoadingAddressData = false;
        _addressDataError = null;
        _syncAddressSelections();
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _isLoadingAddressData = false;
        _addressDataError =
            'Philippine address choices could not be loaded. Please retry.';
      });
    }
  }

  void _loadPatientDetails() {
    final repository = _profileRepository;
    final session = _session;
    if (repository == null || session == null || _isLoadingProfile) return;
    _isLoadingProfile = true;
    final generation = ++_loadGeneration;
    unawaited(_fetchPatientDetails(repository, session, generation));
  }

  Future<void> _fetchPatientDetails(
    PatientProfileRepository repository,
    PatientSession session,
    int generation,
  ) async {
    try {
      final details = await repository.getPatientDetails(
        patientId: session.patientId,
        token: session.token,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _applyDetails(details);
        _didLoadInitialDetails = true;
        _isLoadingProfile = false;
        _loadError = null;
      });
    } on ApiFailure catch (failure) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _isLoadingProfile = false;
        _loadError = failure.message;
      });
    } on Exception catch (error, stackTrace) {
      if (!mounted || generation != _loadGeneration) return;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError(
            'Unexpected edit-profile details failure (${error.runtimeType}).',
          ),
          stack: stackTrace,
          library: 'patient edit profile',
        ),
      );
      setState(() {
        _isLoadingProfile = false;
        _loadError = 'Your profile could not be loaded. Please try again.';
      });
    }
  }

  void _applyDetails(PatientProfileDetails details) {
    final fullName = [
      details.firstName,
      details.middleName,
      details.lastName,
    ].whereType<String>().where((part) => part.trim().isNotEmpty).toList();
    if (fullName.isEmpty) {
      final sessionName = (widget.initialName ?? _session?.name)?.trim();
      if (sessionName != null && sessionName.isNotEmpty) {
        final nameParts = sessionName.split(RegExp(r'\s+'));
        _controllers['firstName']!.text = nameParts.first;
        if (nameParts.length > 1) {
          _controllers['lastName']!.text = nameParts.last;
          if (nameParts.length > 2) {
            _controllers['middleName']!.text = nameParts
                .sublist(1, nameParts.length - 1)
                .join(' ');
          }
        }
      }
    } else {
      _controllers['firstName']!.text = details.firstName ?? '';
      _controllers['middleName']!.text = details.middleName ?? '';
      _controllers['lastName']!.text = details.lastName ?? '';
    }
    _controllers['dateOfBirth']!.text = details.dateOfBirth ?? '';
    _controllers['age']!.text =
        _calculateAge(details.dateOfBirth ?? '')?.toString() ?? '';
    _controllers['contact']!.text = details.contactNumber ?? '';
    _controllers['addressUnit']!.text = details.addressUnit ?? '';
    _controllers['addressStreet']!.text = details.street ?? '';
    _controllers['addressBarangay']!.text = details.barangay ?? '';
    _controllers['addressCityMunicipality']!.text =
        details.cityMunicipality ?? '';
    _controllers['addressProvince']!.text = details.province ?? '';
    _controllers['addressZipCode']!.text = details.zipCode ?? '';
    _controllers['gender']!.text = details.gender ?? '';
    _syncAddressSelections();
  }

  void _syncAddressSelections() {
    final catalog = _addressCatalog;
    if (catalog == null) return;

    final province = _findAddressOptionByName(
      catalog.provinces,
      _controllers['addressProvince']!.text,
    );
    final city = province == null
        ? null
        : _findAddressOptionByName(
            catalog.municipalitiesFor(province.id),
            _controllers['addressCityMunicipality']!.text,
          );
    final barangay = city == null
        ? null
        : _findAddressOptionByName(
            catalog.barangaysFor(city.id),
            _controllers['addressBarangay']!.text,
          );

    _provinceId = province?.id;
    _cityId = city?.id;
    _barangayId = barangay?.id;
  }

  PhilippineAddressOption? _findAddressOptionByName(
    List<PhilippineAddressOption> options,
    String value,
  ) {
    final normalized = _normalizeAddressName(value);
    if (normalized.isEmpty) return null;
    for (final option in options) {
      if (_normalizeAddressName(option.name) == normalized) return option;
    }
    return null;
  }

  String _normalizeAddressName(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(
          RegExp(r'^(city of|municipality of|province of|barangay )'),
          '',
        )
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  Future<void> _retryLoadProfile() async {
    if (_isLoadingProfile) return;
    _didLoadInitialDetails = false;
    _loadPatientDetails();
    setState(() {});
  }

  String _value(String id) => _controllers[id]!.text.trim();

  void _onChanged(String id, String value) {
    setState(() {
      if (id == 'dateOfBirth') {
        _controllers['age']!.text = _calculateAge(value)?.toString() ?? '';
      }
      _status = null;
    });
  }

  int? _calculateAge(String value) {
    final date = _parseDate(value);
    if (date == null) return null;
    final today = DateTime.now();
    var age = today.year - date.year;
    if (today.month < date.month ||
        (today.month == date.month && today.day < date.day)) {
      age--;
    }
    return age;
  }

  Future<void> _selectDateOfBirth() async {
    FocusScope.of(context).unfocus();
    final existingDate = _parseDate(_controllers['dateOfBirth']!.text);
    final initial = existingDate ?? DateTime(DateTime.now().year - 18, 1, 1);
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateUtils.dateOnly(DateTime.now()),
      helpText: 'Select Date of Birth',
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext, child) => Theme(
        data: Theme.of(dialogContext),
        child: MediaQuery(
          data: MediaQuery.of(dialogContext)
              .copyWith(textScaler: TextScaler.noScaling),
          child: child!,
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final value =
        '${selected.year.toString().padLeft(4, '0')}-'
        '${selected.month.toString().padLeft(2, '0')}-'
        '${selected.day.toString().padLeft(2, '0')}';
    setState(() {
      _controllers['dateOfBirth']!.text = value;
      _controllers['age']!.text = _calculateAge(value)?.toString() ?? '';
      _status = null;
    });
  }

  DateTime? _parseDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value.trim());
    if (match == null) return null;
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  String? _validateText(String id) {
    final value = _value(id);
    switch (id) {
      case 'firstName':
        return _requiredText(value, 'Please enter your first name.', 2);
      case 'middleName':
        return value.isNotEmpty && value.length < 2
            ? 'Enter at least 2 characters or leave this blank.'
            : null;
      case 'lastName':
        return _requiredText(value, 'Please enter your last name.', 2);
      case 'gender':
        return _requiredText(value, 'Please enter your gender.');
      case 'dateOfBirth':
        final date = _parseDate(value);
        if (value.isEmpty) return 'Please select your date of birth.';
        if (date == null) return 'Please enter a valid date (YYYY-MM-DD).';
        if (date.isAfter(DateTime.now())) {
          return 'Date of birth cannot be in the future.';
        }
        final age = _calculateAge(value);
        if (age == null || age < 10 || age > 99) {
          return 'Age must be between 10 and 99.';
        }
        return null;
      case 'contact':
        if (value.isEmpty) return 'Please enter your contact number.';
        if (!RegExp(r'^(\+63|0)9\d{9}$')
            .hasMatch(value.replaceAll(RegExp(r'[\s-]'), ''))) {
          return 'Please enter a valid Philippine mobile number.';
        }
        return null;
      case 'addressUnit':
        return _requiredText(
          value,
          'Please enter your house, unit, lot, or block.',
        );
      case 'addressStreet':
        return _requiredText(value, 'Please enter your street.');
      case 'addressBarangay':
        return _requiredText(value, 'Please enter your barangay.');
      case 'addressCityMunicipality':
        return _requiredText(value, 'Please enter your city or municipality.');
      case 'addressProvince':
        return _requiredText(value, 'Please enter your province.');
      case 'addressZipCode':
        if (value.isEmpty) return 'Please enter your ZIP code.';
        if (!RegExp(r'^\d{4}$').hasMatch(value)) {
          return 'ZIP code must be exactly 4 digits.';
        }
        return null;
      default:
        return null;
    }
  }

  String? _requiredText(String value, String message, [int minLength = 1]) {
    if (value.isEmpty) return message;
    if (value.length < minLength) {
      return 'Please enter at least $minLength characters.';
    }
    return null;
  }

  void _saveProfile() {
    final valid = _formKey.currentState!.validate();
    setState(() {
      _status = valid
          ? 'Profile updates are not connected to the clinic API. Nothing was saved.'
          : null;
    });
  }

  void _cancel() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    _formKey.currentState?.reset();
    for (final field in _fields) {
      _controllers[field.id]!.text = _initialValue(field.id);
    }
    setState(() {
      _status = 'Edits were cleared. No changes were saved to the clinic.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width <= PatientPortalBreakpoints.mobile;
    final pagePadding = compact
        ? 16.0
        : width <= 800
        ? 22.0
        : 30.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackedFields = constraints.maxWidth - pagePadding * 2 < 700;
        return SingleChildScrollView(
          key: const ValueKey('edit-profile-scroll'),
          padding: EdgeInsets.fromLTRB(
            pagePadding,
            compact ? 22 : 30,
            pagePadding,
            compact ? 32 : 45,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PageHeader(compact: compact),
                    if (_isLoadingProfile) ...[
                      const SizedBox(height: 14),
                      const LinearProgressIndicator(
                        key: ValueKey('edit-profile-loading'),
                      ),
                    ],
                    if (_loadError != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _loadError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _retryLoadProfile,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Retry loading profile'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    _ProfileSection(
                      title: 'Personal Information',
                      description: 'Update your basic patient information.',
                      icon: Icons.person_outline,
                      child: Column(
                        children: [
                          _fieldRow([
                            _textField('firstName', 'First Name *'),
                            _textField('middleName', 'Middle Name'),
                            _textField('lastName', 'Last Name *'),
                          ], stackedFields),
                          const SizedBox(height: 16),
                          _fieldRow([
                            _textField(
                              'dateOfBirth',
                              'Date of Birth *',
                              hint: 'YYYY-MM-DD',
                              readOnly: true,
                              onTap: _selectDateOfBirth,
                            ),
                            _textField(
                              'age',
                              'Age (calculated; read-only)',
                              readOnly: true,
                              hint: 'Calculated from date of birth',
                            ),
                            _textField('gender', 'Gender *'),
                          ], stackedFields),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _ProfileSection(
                      title: 'Contact Information',
                      description:
                          'Contact details associated with your account.',
                      icon: Icons.contact_mail_outlined,
                      child: _fieldRow([
                        _textField(
                          'contact',
                          'Contact Number *',
                          hint: '09XXXXXXXXX',
                          keyboardType: TextInputType.phone,
                        ),
                      ], stackedFields),
                    ),
                    const SizedBox(height: 18),
                    _ProfileSection(
                      title: 'Address',
                      description:
                          'Your residential address from your clinic account.',
                      icon: Icons.location_on_outlined,
                      child: Column(
                        children: [
                          _fieldRow([
                            _textField(
                              'addressUnit',
                              'House / Unit / Lot / Block *',
                            ),
                            _textField('addressStreet', 'Street *'),
                          ], stackedFields),
                          const SizedBox(height: 16),
                          if (_isLoadingAddressData)
                            const LinearProgressIndicator(
                              key: ValueKey('edit-profile-address-loading'),
                              minHeight: 3,
                            ),
                          if (_addressDataError != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _isLoadingAddressData = true;
                                    _addressDataError = null;
                                  });
                                  unawaited(_loadAddressCatalog());
                                },
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Retry address choices'),
                              ),
                            ),
                          _fieldRow([
                            _addressDropdown(
                              id: 'addressProvince',
                              label: 'Province *',
                              hint: 'Select Province',
                              value: _provinceId,
                              options: _addressCatalog?.provinces ?? const [],
                              onChanged: (provinceId) {
                                final option = _addressOption(
                                  _addressCatalog?.provinces ?? const [],
                                  provinceId,
                                );
                                setState(() {
                                  _provinceId = provinceId;
                                  _cityId = null;
                                  _barangayId = null;
                                  _controllers['addressProvince']!.text =
                                      option?.name ?? '';
                                  _controllers['addressCityMunicipality']!
                                          .text =
                                      '';
                                  _controllers['addressBarangay']!.text = '';
                                  _status = null;
                                });
                              },
                            ),
                            _addressDropdown(
                              id: 'addressCityMunicipality',
                              label: 'City / Municipality *',
                              hint: _provinceId == null
                                  ? 'Select Province First'
                                  : 'Select City / Municipality',
                              value: _cityId,
                              options: _provinceId == null
                                  ? const []
                                  : _addressCatalog?.municipalitiesFor(
                                          _provinceId!,
                                        ) ??
                                        const [],
                              onChanged: (cityId) {
                                final options = _provinceId == null
                                    ? const <PhilippineAddressOption>[]
                                    : _addressCatalog?.municipalitiesFor(
                                            _provinceId!,
                                          ) ??
                                          const <PhilippineAddressOption>[];
                                final option = _addressOption(options, cityId);
                                setState(() {
                                  _cityId = cityId;
                                  _barangayId = null;
                                  _controllers['addressCityMunicipality']!
                                          .text =
                                      option?.name ?? '';
                                  _controllers['addressBarangay']!.text = '';
                                  _status = null;
                                });
                              },
                            ),
                          ], stackedFields),
                          const SizedBox(height: 16),
                          _fieldRow([
                            _addressDropdown(
                              id: 'addressBarangay',
                              label: 'Barangay *',
                              hint: _cityId == null
                                  ? 'Select City / Municipality First'
                                  : 'Select Barangay',
                              value: _barangayId,
                              options: _cityId == null
                                  ? const []
                                  : _addressCatalog?.barangaysFor(_cityId!) ??
                                        const [],
                              onChanged: (barangayId) {
                                final options = _cityId == null
                                    ? const <PhilippineAddressOption>[]
                                    : _addressCatalog?.barangaysFor(_cityId!) ??
                                          const <PhilippineAddressOption>[];
                                final option = _addressOption(
                                  options,
                                  barangayId,
                                );
                                setState(() {
                                  _barangayId = barangayId;
                                  _controllers['addressBarangay']!.text =
                                      option?.name ?? '';
                                  _status = null;
                                });
                              },
                            ),
                            _textField(
                              'addressZipCode',
                              'ZIP Code *',
                              hint: 'e.g. 3019',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(4),
                              ],
                            ),
                          ], stackedFields),
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
                        final save = FilledButton.icon(
                          key: const ValueKey('edit-profile-save'),
                          onPressed: _saveProfile,
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Save Changes'),
                        );
                        final cancel = OutlinedButton.icon(
                          key: const ValueKey('edit-profile-cancel'),
                          onPressed: _cancel,
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('Cancel'),
                        );
                        if (vertical) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(height: 48, child: save),
                              const SizedBox(height: 10),
                              SizedBox(height: 46, child: cancel),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: SizedBox(height: 48, child: save)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(height: 48, child: cancel),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Profile updates are not connected to the clinic API.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .extension<PatientPortalTextColors>()!
                            .secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _fieldRow(List<Widget> fields, bool stacked) {
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _withSpacing(fields, 14),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _withSpacing(
        fields.map((field) => Expanded(child: field)).toList(),
        14,
        horizontal: true,
      ),
    );
  }

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

  PhilippineAddressOption? _addressOption(
    List<PhilippineAddressOption> options,
    String? id,
  ) {
    for (final option in options) {
      if (option.id == id) return option;
    }
    return null;
  }

  Widget _addressDropdown({
    required String id,
    required String label,
    required String hint,
    required String? value,
    required List<PhilippineAddressOption> options,
    required ValueChanged<String?> onChanged,
  }) {
    final selectedValue = options.any((option) => option.id == value)
        ? value
        : null;
    return _LabeledField(
      label: label,
      child: DropdownButtonFormField<String>(
        key: ValueKey('edit-profile-$id'),
        initialValue: selectedValue,
        isExpanded: true,
        validator: (_) => _validateText(id),
        onChanged: _addressCatalog == null ? null : onChanged,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 14,
          ),
        ),
        items: options
            .map(
              (option) => DropdownMenuItem<String>(
                value: option.id,
                child: Text(option.name, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _textField(
    String id,
    String label, {
    String? hint,
    TextInputType? keyboardType,
    bool readOnly = false,
    VoidCallback? onTap,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return _LabeledField(
      label: label,
      child: TextFormField(
        key: ValueKey('edit-profile-$id'),
        controller: _controllers[id],
        readOnly: readOnly,
        keyboardType: keyboardType,
        onTap: onTap,
        inputFormatters: inputFormatters,
        onChanged: (value) => _onChanged(id, value),
        validator: (_) => _validateText(id),
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 14,
          ),
          suffixIcon: id == 'age'
              ? const Icon(Icons.lock_outline_rounded, size: 17)
              : id == 'dateOfBirth'
              ? const Icon(Icons.calendar_today_outlined, size: 19)
              : null,
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
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'PREVIEW ONLY',
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
          badge,
        ] else
          Row(children: [brand, const Spacer(), badge]),
        const SizedBox(height: 10),
        Text(
          'Edit Profile',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: compact ? 26 : 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'Review the information you enter below. Profile updates are not '
          'connected to the clinic API.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: secondary,
            height: 1.55,
          ),
        ),
      ],
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.title,
    required this.description,
    required this.icon,
    required this.child,
  });

  final String title;
  final String description;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: theme.colorScheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
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
        child,
      ],
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('edit-profile-status'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF1D4ED8),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _initialValue(String id) {
  return '';
}

const _fields = <_FieldDefinition>[
  _FieldDefinition('firstName'),
  _FieldDefinition('middleName'),
  _FieldDefinition('lastName'),
  _FieldDefinition('dateOfBirth'),
  _FieldDefinition('age'),
  _FieldDefinition('gender'),
  _FieldDefinition('contact'),
  _FieldDefinition('addressUnit'),
  _FieldDefinition('addressStreet'),
  _FieldDefinition('addressBarangay'),
  _FieldDefinition('addressCityMunicipality'),
  _FieldDefinition('addressProvince'),
  _FieldDefinition('addressZipCode'),
];

class _FieldDefinition {
  const _FieldDefinition(this.id);
  final String id;
}
