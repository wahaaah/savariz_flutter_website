import 'package:flutter_test/flutter_test.dart';

import 'package:patient_portal_flutter/features/auth/data/philippine_address_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads the bundled Philippine address catalog', () async {
    final catalog = await PhilippineAddressCatalog.load();

    expect(catalog.provinces, hasLength(87));
    expect(catalog.citiesMunicipalities, hasLength(1629));
    expect(catalog.barangays, hasLength(41581));

    final bulacan = catalog.provinces.singleWhere(
      (province) => province.code == '0314',
    );
    expect(bulacan.name, 'BULACAN');

    final bulacanCities = catalog.municipalitiesFor(bulacan.code!);
    expect(bulacanCities, isNotEmpty);
    final meycauayan = bulacanCities.singleWhere(
      (city) => city.name == 'CITY OF MEYCAUAYAN',
    );
    expect(catalog.barangaysFor(meycauayan.code!), isNotEmpty);
  });

  test('rejects malformed address data', () {
    expect(
      () => PhilippineAddressCatalog.fromJson(
        provinces: const [],
        citiesMunicipalities: const [],
        barangays: const [],
      ),
      throwsFormatException,
    );
  });
}
