import '../../../core/network/api_client.dart';
import '../../../core/network/api_failure.dart';
import 'catalog_frame.dart';

abstract interface class FramesCatalogRepository {
  Future<List<CatalogFrame>> getFrames();
}

class ApiFramesCatalogRepository implements FramesCatalogRepository {
  const ApiFramesCatalogRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<CatalogFrame>> getFrames() async {
    try {
      final rows = await _apiClient.getJsonList('/api/frames');
      return rows
          .map((row) {
            if (row is! Map<String, dynamic>) {
              throw const FormatException('Invalid frame catalog entry.');
            }
            return CatalogFrame.fromJson(row, assetBaseUri: _apiClient.baseUri);
          })
          .toList(growable: false);
    } on FormatException {
      throw const ApiFailure(
        kind: ApiFailureKind.invalidResponse,
        message: 'The clinic service returned an invalid frame catalog.',
      );
    }
  }
}
