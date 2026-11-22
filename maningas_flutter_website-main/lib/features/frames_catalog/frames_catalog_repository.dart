import '../../../core/network/api_client.dart';
import '../../../core/network/api_failure.dart';
import 'catalog_frame.dart';

abstract interface class FramesCatalogRepository {
  Future<CatalogFramePage> getFrames({
    required int page,
    required int limit,
    required String search,
    required String category,
    required String availability,
    required String sort,
  });
}

class CatalogFramePage {
  const CatalogFramePage({
    required this.frames,
    required this.categories,
    required this.page,
    required this.total,
    required this.totalPages,
  });

  final List<CatalogFrame> frames;
  final List<String> categories;
  final int page;
  final int total;
  final int totalPages;
}

class ApiFramesCatalogRepository implements FramesCatalogRepository {
  const ApiFramesCatalogRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<CatalogFramePage> getFrames({
    required int page,
    required int limit,
    required String search,
    required String category,
    required String availability,
    required String sort,
  }) async {
    try {
      final query = Uri(
        queryParameters: {
          'page': '$page',
          'limit': '$limit',
          'search': search,
          'category': category,
          'availability': availability,
          'sort': sort,
        },
      );
      final response = await _apiClient.getJson(
        '/api/frames/page?${query.query}',
      );
      final rows = response['items'];
      final pagination = response['pagination'];
      final rawCategories = response['categories'];
      if (rows is! List<Object?> ||
          pagination is! Map<String, dynamic> ||
          rawCategories is! List<Object?>) {
        throw const FormatException('Invalid paginated frame catalog.');
      }
      final frames = rows
          .map((row) {
            if (row is! Map<String, dynamic>) {
              throw const FormatException('Invalid frame catalog entry.');
            }
            return CatalogFrame.fromJson(row, assetBaseUri: _apiClient.baseUri);
          })
          .toList(growable: false);
      final categories = rawCategories
          .whereType<String>()
          .toList(growable: false);
      return CatalogFramePage(
        frames: frames,
        categories: categories,
        page: _paginationValue(pagination['page']),
        total: _paginationValue(pagination['total']),
        totalPages: _paginationValue(pagination['totalPages']),
      );
    } on FormatException {
      throw const ApiFailure(
        kind: ApiFailureKind.invalidResponse,
        message: 'The clinic service returned an invalid frame catalog.',
      );
    }
  }
}

int _paginationValue(Object? value) {
  if (value is int && value >= 0) return value;
  if (value is num && value >= 0) return value.toInt();
  throw const FormatException('Invalid frame pagination metadata.');
}
