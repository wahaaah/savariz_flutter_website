import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_failure.dart';

class ApiClient {
  ApiClient({
    required this.client,
    required this.baseUri,
    this.timeout = const Duration(seconds: 15),
  });

  final http.Client client;
  final Uri baseUri;
  final Duration timeout;

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String> headers = const {},
  }) async {
    return _sendJson(
      () => client.get(baseUri.resolve(path), headers: _headers(headers)),
    ).then((decoded) => decoded as Map<String, dynamic>);
  }

  Future<List<Object?>> getJsonList(
    String path, {
    Map<String, String> headers = const {},
  }) async {
    return _sendJson(
      () => client.get(baseUri.resolve(path), headers: _headers(headers)),
      expectList: true,
    ).then((decoded) => decoded as List<Object?>);
  }

  Future<Object> getJsonMapOrList(
    String path, {
    Map<String, String> headers = const {},
  }) {
    return _sendJson(
      () => client.get(baseUri.resolve(path), headers: _headers(headers)),
      allowList: true,
    );
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    required Map<String, Object?> body,
    Map<String, String> headers = const {},
  }) async {
    return _sendJson(
      () => client.post(
        baseUri.resolve(path),
        headers: _headers(headers),
        body: jsonEncode(body),
      ),
    ).then((decoded) => decoded as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> patchJson(
    String path, {
    Map<String, Object?>? body,
    Map<String, String> headers = const {},
  }) async {
    return _sendJson(
      () => client.patch(
        baseUri.resolve(path),
        headers: _headers(headers),
        body: body == null ? null : jsonEncode(body),
      ),
    ).then((decoded) => decoded as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> putJson(
    String path, {
    Map<String, Object?>? body,
    Map<String, String> headers = const {},
  }) async {
    return _sendJson(
      () => client.put(
        baseUri.resolve(path),
        headers: _headers(headers),
        body: body == null ? null : jsonEncode(body),
      ),
      allowEmptyResponse: true,
    ).then((decoded) => decoded as Map<String, dynamic>);
  }

  Map<String, String> _headers(Map<String, String> headers) => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    ...headers,
  };

  Future<Object> _sendJson(
    Future<http.Response> Function() send, {
    bool expectList = false,
    bool allowList = false,
    bool allowEmptyResponse = false,
  }) async {
    late final http.Response response;
    try {
      response = await send().timeout(timeout);
    } on TimeoutException {
      throw const ApiFailure(
        kind: ApiFailureKind.timeout,
        message: 'The request timed out. Please try again.',
      );
    } on http.ClientException {
      throw const ApiFailure(
        kind: ApiFailureKind.network,
        message: 'Unable to reach the clinic service. Check your connection.',
      );
    }

    Object? decoded;
    try {
      decoded = response.body.isEmpty && allowEmptyResponse
          ? <String, dynamic>{}
          : jsonDecode(response.body);
    } on FormatException {
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiFailure(
          kind: ApiFailureKind.http,
          statusCode: response.statusCode,
          message: _httpErrorMessage(response.statusCode),
        );
      }
      throw const ApiFailure(
        kind: ApiFailureKind.invalidResponse,
        message: 'The clinic service returned an invalid response.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (decoded is! Map<String, dynamic>) {
        throw const ApiFailure(
          kind: ApiFailureKind.invalidResponse,
          message: 'The clinic service returned an invalid response.',
        );
      }

      final message = decoded['error'] ?? decoded['message'];
      throw ApiFailure(
        kind: ApiFailureKind.http,
        statusCode: response.statusCode,
        code: decoded['code'] is String ? decoded['code'] as String : null,
        message:
            response.statusCode < 500 &&
                message is String &&
                message.trim().isNotEmpty
            ? message.trim()
            : _httpErrorMessage(response.statusCode),
      );
    }

    if ((expectList || allowList) && decoded is List) {
      return List<Object?>.of(decoded);
    }
    if (!expectList && decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const ApiFailure(
      kind: ApiFailureKind.invalidResponse,
      message: 'The clinic service returned an invalid response.',
    );
  }

  String _httpErrorMessage(int statusCode) => switch (statusCode) {
    401 => 'Invalid email or password.',
    403 => 'This account cannot sign in. Contact the clinic for assistance.',
    >= 500 => 'The clinic service is temporarily unavailable.',
    _ => 'The request could not be completed.',
  };

  void close() => client.close();
}
