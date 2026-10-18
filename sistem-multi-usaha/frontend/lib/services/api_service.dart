import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Karena Flutter Web dilayani langsung oleh server Rust di port 8000,
  // baseUrl bisa menggunakan origin yang sama secara dinamis.
  static const String baseUrl = 'http://127.0.0.1:8000/api';
  static String? authToken;

  static Map<String, String> get headers {
    final map = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
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
      final res = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: headers,
        body: jsonEncode(body),
      );
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      // Fallback
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
