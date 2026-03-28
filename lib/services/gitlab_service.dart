import 'dart:convert';
import 'api_client.dart';

class GitLabService {
  final String domain;
  final String token;
  late final Map<String, String> _headers;
  final Map<String, _CacheEntry> _cache = {};

  GitLabService({required this.domain, required this.token}) {
    _headers = {
      'PRIVATE-TOKEN': token,
      'Accept': 'application/json',
    };
  }

  Future<dynamic> _get(String url, String cacheKey, {Duration ttl = const Duration(minutes: 3)}) async {
    final cached = _cache[cacheKey];
    if (cached != null && DateTime.now().isBefore(cached.expiresAt)) return cached.data;

    final res = await ApiClient.get(url, headers: _headers);
    if (res.statusCode != 200) throw Exception('GitLab ${res.statusCode}: ${res.reasonPhrase}');
    final data = jsonDecode(res.body);
    _cache[cacheKey] = _CacheEntry(data, DateTime.now().add(ttl));
    return data;
  }

  void clearCache() => _cache.clear();

  Future<Map<String, dynamic>> getUser() async =>
      await _get('https://$domain/api/v4/user', 'user', ttl: const Duration(minutes: 10));

  Future<List<dynamic>> getMyMRs() async {
    final data = await _get(
      'https://$domain/api/v4/merge_requests?state=opened&scope=created_by_me&per_page=30&order_by=updated_at',
      'my_mrs',
    );
    return data is List ? data : [];
  }

  Future<List<dynamic>> getReviewRequests() async {
    final data = await _get(
      'https://$domain/api/v4/merge_requests?state=opened&scope=assigned_to_me&per_page=30&order_by=updated_at',
      'review_reqs',
    );
    return data is List ? data : [];
  }

  Future<List<dynamic>> getAssignedIssues() async {
    final data = await _get(
      'https://$domain/api/v4/issues?state=opened&scope=assigned_to_me&per_page=30&order_by=updated_at',
      'assigned_issues',
    );
    return data is List ? data : [];
  }

  Future<List<dynamic>> getTodos() async {
    final data = await _get(
      'https://$domain/api/v4/todos?state=pending&per_page=30',
      'todos',
      ttl: const Duration(minutes: 2),
    );
    return data is List ? data : [];
  }
}

class _CacheEntry {
  final dynamic data;
  final DateTime expiresAt;
  _CacheEntry(this.data, this.expiresAt);
}
