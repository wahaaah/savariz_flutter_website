import '../../../core/network/api_client.dart';
import '../../../core/network/api_failure.dart';
import 'transaction_record.dart';

abstract interface class TransactionHistoryRepository {
  Future<TransactionHistoryPageResult> getTransactions({
    required String patientId,
    required String token,
    required int page,
    required int limit,
  });
}

class TransactionHistoryPageResult {
  const TransactionHistoryPageResult({
    required this.items,
    required this.total,
    required this.totalPages,
  });

  final List<TransactionRecord> items;
  final int total;
  final int totalPages;
}

class ApiTransactionHistoryRepository implements TransactionHistoryRepository {
  const ApiTransactionHistoryRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<TransactionHistoryPageResult> getTransactions({
    required String patientId,
    required String token,
    required int page,
    required int limit,
  }) async {
    try {
      final response = await _apiClient.getJson(
        '/api/patients/${Uri.encodeComponent(patientId)}/transactions'
        '?page=$page&limit=$limit',
        headers: {'Authorization': 'Bearer $token'},
      );
      final rows = response['transactions'];
      final pagination = response['pagination'];
      if (response['success'] != true ||
          rows is! List<Object?> ||
          pagination is! Map<String, dynamic>) {
        throw const FormatException('Invalid transaction history response.');
      }
      final records = <TransactionRecord>[];
      for (final row in rows) {
        if (row is! Map<String, dynamic>) {
          throw const FormatException('Invalid transaction record.');
        }
        records.add(TransactionRecord.fromJson(row));
      }
      final total = _parsePaginationInteger(pagination['total']);
      final totalPages = _parsePaginationInteger(pagination['totalPages']);
      if (total == null || totalPages == null) {
        throw const FormatException('Invalid transaction pagination metadata.');
      }
      return TransactionHistoryPageResult(
        items: records,
        total: total,
        totalPages: totalPages,
      );
    } on FormatException {
      throw const ApiFailure(
        kind: ApiFailureKind.invalidResponse,
        message: 'The clinic service returned invalid transaction history.',
      );
    } on ApiFailure catch (failure) {
      if (failure.statusCode == 401 || failure.statusCode == 403) {
        throw ApiFailure(
          kind: failure.kind,
          statusCode: failure.statusCode,
          code: failure.code,
          message: failure.statusCode == 401
              ? 'Your patient session is invalid or expired. Please sign in again.'
              : 'Your account cannot access transaction history.',
        );
      }
      rethrow;
    }
  }

  int? _parsePaginationInteger(Object? value) {
    if (value is int && value >= 0) return value;
    if (value is num && value >= 0 && value == value.toInt()) {
      return value.toInt();
    }
    return null;
  }
}
