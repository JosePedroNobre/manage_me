import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// Proxy-aware HTTP client.
///
/// On Flutter Web, browsers block cross-origin API calls (CORS).
/// This client routes requests through a local CORS proxy when running on web.
/// On mobile/desktop there is no CORS restriction, so calls go direct.
class ApiClient {
  static String _proxyBase = 'http://localhost:9090';

  /// Set the CORS proxy base URL (no trailing slash).
  static void setProxy(String url) => _proxyBase = url;
  static String get proxyBase => _proxyBase;

  /// Whether we need a proxy (only on web).
  static bool get needsProxy => kIsWeb;

  /// Rewrite a URL to go through the proxy when on web.
  static String proxyUrl(String originalUrl) {
    if (!needsProxy) return originalUrl;
    // The proxy expects: http://localhost:9090/<target-url>
    return '$_proxyBase/$originalUrl';
  }

  /// GET with proxy support.
  static Future<http.Response> get(String url, {Map<String, String>? headers}) {
    return http.get(Uri.parse(proxyUrl(url)), headers: headers);
  }

  /// POST with proxy support.
  static Future<http.Response> post(String url, {Map<String, String>? headers, String? body}) {
    final h = {...?headers, 'Content-Type': 'application/json'};
    return http.post(Uri.parse(proxyUrl(url)), headers: h, body: body);
  }

  /// PUT with proxy support.
  static Future<http.Response> put(String url, {Map<String, String>? headers, String? body}) {
    final h = {...?headers, 'Content-Type': 'application/json'};
    return http.put(Uri.parse(proxyUrl(url)), headers: h, body: body);
  }
}
