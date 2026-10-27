import 'dart:convert';

import 'package:flutter/services.dart';

class PhilippineAddressOption {
  const PhilippineAddressOption({
    required this.id,
    required this.name,
    required this.code,
    this.parentCode,
  });

  final String id;
  final String name;
  final String? code;
  final String? parentCode;
}

class PhilippineAddressCatalog {
  PhilippineAddressCatalog({
    required this.provinces,
    required this.citiesMunicipalities,
    required this.barangays,
  }) : _citiesByProvince = _groupByParentCode(citiesMunicipalities),
     _barangaysByMunicipality = _groupByParentCode(barangays);

  final List<PhilippineAddressOption> provinces;
  final List<PhilippineAddressOption> citiesMunicipalities;
  final List<PhilippineAddressOption> barangays;
  final Map<String, List<PhilippineAddressOption>> _citiesByProvince;
  final Map<String, List<PhilippineAddressOption>> _barangaysByMunicipality;

  static Future<PhilippineAddressCatalog> load() async {
    final provinceJson = await rootBundle.loadString(
      'assets/philippine_addresses/provinces.json',
    );
    final cityJson = await rootBundle.loadString(
      'assets/philippine_addresses/cities_municipalities.json',
    );
    final barangayJson = await rootBundle.loadString(
      'assets/philippine_addresses/barangays.json',
    );
    return PhilippineAddressCatalog.fromJson(
      provinces: jsonDecode(provinceJson),
      citiesMunicipalities: jsonDecode(cityJson),
      barangays: jsonDecode(barangayJson),
    );
  }

  factory PhilippineAddressCatalog.fromJson({
    required Object? provinces,
    required Object? citiesMunicipalities,
    required Object? barangays,
  }) {
    final provinceRows = _rows(provinces, 'province');
    final cityRows = _rows(citiesMunicipalities, 'city/municipality');
    // The upstream dataset contains a blank-named barangay; omit it as an option.
    final barangayRows = _rows(barangays, 'barangay').where((row) {
      final name = row['name'];
      return name is String && name.trim().isNotEmpty;
    }).toList();

    final provinceOptions = <String, PhilippineAddressOption>{};
    for (final row in provinceRows) {
      final code = _requiredString(row, 'prov_code', 'province code');
      final name = _requiredString(row, 'name', 'province name');
      final current = provinceOptions[code];
      if (current == null ||
          (current.name.startsWith('NCR,') && !name.startsWith('NCR,'))) {
        provinceOptions[code] = PhilippineAddressOption(
          id: code,
          name: name,
          code: code,
        );
      }
    }

    final cityOptions = [
      for (final row in cityRows)
        PhilippineAddressOption(
          id: _requiredString(row, 'mun_code', 'municipality code'),
          name: _requiredString(row, 'name', 'city/municipality name'),
          code: _requiredString(row, 'mun_code', 'municipality code'),
          parentCode: _requiredString(row, 'prov_code', 'province code'),
        ),
    ];
    final barangayOptions = [
      for (var index = 0; index < barangayRows.length; index++)
        PhilippineAddressOption(
          id: '$index',
          name: _requiredString(barangayRows[index], 'name', 'barangay name'),
          code: null,
          parentCode: _requiredString(
            barangayRows[index],
            'mun_code',
            'municipality code',
          ),
        ),
    ];

    if (provinceOptions.isEmpty ||
        cityOptions.isEmpty ||
        barangayOptions.isEmpty) {
      throw const FormatException('Philippine address data is incomplete.');
    }

    return PhilippineAddressCatalog(
      provinces: List.unmodifiable(provinceOptions.values),
      citiesMunicipalities: List.unmodifiable(cityOptions),
      barangays: List.unmodifiable(barangayOptions),
    );
  }

  List<PhilippineAddressOption> municipalitiesFor(String provinceCode) =>
      _citiesByProvince[provinceCode] ?? const [];

  List<PhilippineAddressOption> barangaysFor(String municipalityCode) =>
      _barangaysByMunicipality[municipalityCode] ?? const [];

  PhilippineAddressOption? provinceByCode(String? code) =>
      _findByCode(provinces, code);

  PhilippineAddressOption? municipalityByCode(String? code) =>
      _findByCode(citiesMunicipalities, code);

  PhilippineAddressOption? barangayById(String? id) => _findById(barangays, id);

  static PhilippineAddressOption? _findById(
    List<PhilippineAddressOption> options,
    String? id,
  ) {
    if (id == null) return null;
    for (final option in options) {
      if (option.id == id) return option;
    }
    return null;
  }

  static PhilippineAddressOption? _findByCode(
    List<PhilippineAddressOption> options,
    String? code,
  ) {
    if (code == null) return null;
    for (final option in options) {
      if (option.code == code) return option;
    }
    return null;
  }

  static Map<String, List<PhilippineAddressOption>> _groupByParentCode(
    List<PhilippineAddressOption> options,
  ) {
    final grouped = <String, List<PhilippineAddressOption>>{};
    for (final option in options) {
      final parentCode = option.parentCode;
      if (parentCode == null) continue;
      grouped.putIfAbsent(parentCode, () => []).add(option);
    }
    return Map<String, List<PhilippineAddressOption>>.unmodifiable({
      for (final entry in grouped.entries)
        entry.key: List<PhilippineAddressOption>.unmodifiable(entry.value),
    });
  }
}

List<Map<String, dynamic>> _rows(Object? value, String label) {
  if (value is! List) {
    throw FormatException('Invalid Philippine $label data.');
  }
  return [
    for (final row in value)
      if (row is Map<String, dynamic>)
        row
      else
        throw FormatException('Invalid Philippine $label entry.'),
  ];
}

String _requiredString(Map<String, dynamic> row, String key, String label) {
  final value = row[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Philippine address data is missing $label.');
  }
  return value.trim();
}
