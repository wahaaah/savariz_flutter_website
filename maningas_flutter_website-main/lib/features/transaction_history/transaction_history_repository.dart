import '../../../core/network/api_client.dart';
import '../../../core/network/api_failure.dart';
import 'transaction_record.dart';

abstract interface class TransactionHistoryRepository {
  Future<List<TransactionRecord>> getTransactions({
    required String patientId,
    required String token,
  });
}

class ApiTransactionHistoryRepository
    implements TransactionHistoryRepository {
  const ApiTransactionHistoryRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<List<TransactionRecord>> getTransactions({
    required String patientId,
    required String token,
  }) async {
    try {
      final response = await _apiClient.getJson(
        '/api/patients/${Uri.encodeComponent(patientId)}/transactions',
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response['success'] != true || response['transactions'] is! List) {
        throw const FormatException('Invalid transaction history response.');
      }
      final records = <TransactionRecord>[];
      for (final row in response['transactions'] as List) {
        if (row is! Map<String, dynamic>) {
          throw const FormatException('Invalid transaction record.');
        }
        records.add(TransactionRecord.fromJson(row));
      }
      return records;
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
}
