import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
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

  // Generic GET
  static Future<Map<String, dynamic>?> get(String endpoint) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl$endpoint'), headers: headers);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      // Fallback
    }
    return null;
  }

  // Generic POST
  static Future<Map<String, dynamic>?> post(String endpoint, Map<String, dynamic> body) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      final res = await http.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      );
      if (res.body.isNotEmpty) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('API POST error on $endpoint: $e');
      return {'status': 'error', 'message': e.toString()};
    }
    return null;
  }

  // Generic PATCH
  static Future<Map<String, dynamic>?> patch(String endpoint, [Map<String, dynamic>? body]) async {
    try {
      final res = await http.patch(
        Uri.parse('$baseUrl$endpoint'),
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      );
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      // Fallback
    }
    return null;
  }

  // Generic DELETE
  static Future<bool> delete(String endpoint) async {
    try {
      final res = await http.delete(Uri.parse('$baseUrl$endpoint'), headers: headers);
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      return false;
    }
  }
}
