import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int? statusCode;
  final String message;
  final String endpoint;

  const ApiException({
    this.statusCode,
    required this.message,
    required this.endpoint,
  });

  @override
  String toString() =>
      'ApiException(statusCode: $statusCode, endpoint: $endpoint, message: $message)';
}

class ApiService {
  static const Duration defaultTimeout = Duration(seconds: 15);

  // Dapat dikonfigurasi saat build menggunakan:
  // flutter build apk --dart-define=BACKEND_URL=http://192.168.1.xx:8000/api
  // Default fallback: http://127.0.0.1:8000/api (untuk Desktop / Local)
  static String get baseUrl {
    const envUrl = String.fromEnvironment('BACKEND_URL');
    if (envUrl.isNotEmpty) return envUrl;
    if (kIsWeb) {
      final origin = Uri.base.origin;
      return '$origin/api';
    }
    return 'http://127.0.0.1:8000/api';
  }

  static String? authToken;

  static Map<String, String> get headers {
    final map = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-Client-Platform': kIsWeb ? 'web' : 'app',
    };
    if (authToken != null && authToken!.isNotEmpty) {
      map['Authorization'] = 'Bearer $authToken';
    }
    return map;
  }

  static Map<String, dynamic> _parseOrError(http.Response res, String endpoint) {
    final isSuccessStatus = res.statusCode >= 200 && res.statusCode < 300;
    if (res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          if (!isSuccessStatus && decoded['status'] == null) {
            decoded['status'] = 'error';
          }
          decoded['statusCode'] = res.statusCode;
          return decoded;
        }
      } catch (e) {
        debugPrint('API JSON decode error on $endpoint (${res.statusCode}): $e');
      }
    }

    if (isSuccessStatus) {
      return {'status': 'success', 'statusCode': res.statusCode};
    }

    final err = ApiException(
      statusCode: res.statusCode,
      endpoint: endpoint,
      message: res.statusCode == 401
          ? 'Sesi tidak valid atau telah berakhir (401).'
          : 'Server mengembalikan status ${res.statusCode}.',
    );
    debugPrint('$err');
    return {
      'status': 'error',
      'statusCode': res.statusCode,
      'message': err.message,
    };
  }

  // Generic GET
  static Future<Map<String, dynamic>?> get(String endpoint) async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl$endpoint'), headers: headers)
          .timeout(defaultTimeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return _parseOrError(res, endpoint);
      }
      final err = _parseOrError(res, endpoint);
      debugPrint('API GET failed on $endpoint (${res.statusCode}): ${err['message']}');
      return err;
    } on TimeoutException {
      final ex = ApiException(
        endpoint: endpoint,
        message: 'Waktu koneksi habis (timeout ${defaultTimeout.inSeconds}s).',
      );
      debugPrint('$ex');
      return {'status': 'error', 'message': ex.message};
    } catch (e) {
      final ex = ApiException(endpoint: endpoint, message: e.toString());
      debugPrint('$ex');
      return {'status': 'error', 'message': ex.message};
    }
  }

  // Generic POST
  static Future<Map<String, dynamic>?> post(
      String endpoint, Map<String, dynamic> body) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      final res = await http
          .post(
            uri,
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(defaultTimeout);
      return _parseOrError(res, endpoint);
    } on TimeoutException {
      final ex = ApiException(
        endpoint: endpoint,
        message: 'Waktu koneksi habis (timeout ${defaultTimeout.inSeconds}s).',
      );
      debugPrint('$ex');
      return {'status': 'error', 'message': ex.message};
    } catch (e) {
      final ex = ApiException(endpoint: endpoint, message: e.toString());
      debugPrint('$ex');
      return {'status': 'error', 'message': ex.message};
    }
  }

  // Generic PATCH
  static Future<Map<String, dynamic>?> patch(String endpoint,
      [Map<String, dynamic>? body]) async {
    try {
      final res = await http
          .patch(
            Uri.parse('$baseUrl$endpoint'),
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(defaultTimeout);
      final parsed = _parseOrError(res, endpoint);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint(
            'API PATCH failed on $endpoint (${res.statusCode}): ${parsed['message']}');
        return {
          ...parsed,
          'status': 'error',
        };
      }
      return parsed;
    } on TimeoutException {
      final ex = ApiException(
        endpoint: endpoint,
        message: 'Waktu koneksi habis (timeout ${defaultTimeout.inSeconds}s).',
      );
      debugPrint('$ex');
      return {'status': 'error', 'message': ex.message};
    } catch (e) {
      final ex = ApiException(endpoint: endpoint, message: e.toString());
      debugPrint('$ex');
      return {'status': 'error', 'message': ex.message};
    }
  }

  // Generic DELETE
  static Future<bool> delete(String endpoint) async {
    try {
      final res = await http
          .delete(Uri.parse('$baseUrl$endpoint'), headers: headers)
          .timeout(defaultTimeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return true;
      }
      debugPrint('API DELETE failed on $endpoint with status ${res.statusCode}');
      return false;
    } on TimeoutException {
      debugPrint(
          'API DELETE timeout on $endpoint (${defaultTimeout.inSeconds}s)');
      return false;
    } catch (e) {
      debugPrint('API DELETE error on $endpoint: $e');
      return false;
    }
  }
}
