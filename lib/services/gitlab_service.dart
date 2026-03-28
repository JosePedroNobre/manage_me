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

  /// Get full issue details
  Future<Map<String, dynamic>> getIssue(int projectId, int iid) async {
    final data = await _get(
      'https://$domain/api/v4/projects/$projectId/issues/$iid',
      'issue_${projectId}_$iid',
      ttl: const Duration(minutes: 5),
    );
    return data is Map<String, dynamic> ? data : {};
  }

  /// Get MR diff (changes)
  Future<List<dynamic>> getMRChanges(int projectId, int iid) async {
    final data = await _get(
      'https://$domain/api/v4/projects/$projectId/merge_requests/$iid/changes',
      'mr_changes_${projectId}_$iid',
      ttl: const Duration(minutes: 3),
    );
    if (data is Map) return data['changes'] as List? ?? [];
    return [];
  }

  /// Get MR diff as raw text
  Future<String> getMRDiff(int projectId, int iid) async {
    final res = await ApiClient.get(
      'https://$domain/api/v4/projects/$projectId/merge_requests/$iid/changes',
      headers: _headers,
    );
    if (res.statusCode != 200) return '';
    final data = jsonDecode(res.body);
    final changes = data['changes'] as List? ?? [];
    final buf = StringBuffer();
    for (final c in changes) {
      buf.writeln('--- ${c['old_path'] ?? ''}');
      buf.writeln('+++ ${c['new_path'] ?? ''}');
      buf.writeln(c['diff'] ?? '');
    }
    return buf.toString();
  }

  /// Post a note (comment) on an MR
  Future<bool> postMRNote(int projectId, int iid, String body) async {
    final res = await ApiClient.post(
      'https://$domain/api/v4/projects/$projectId/merge_requests/$iid/notes',
      headers: _headers,
      body: jsonEncode({'body': body}),
    );
    return res.statusCode == 201;
  }

  /// Post a note (comment) on an issue
  Future<bool> postIssueNote(int projectId, int iid, String body) async {
    final res = await ApiClient.post(
      'https://$domain/api/v4/projects/$projectId/issues/$iid/notes',
      headers: _headers,
      body: jsonEncode({'body': body}),
    );
    return res.statusCode == 201;
  }

  /// Get issue URL
  String issueUrl(String webUrl) => webUrl;

  /// Get MR URL
  String mrUrl(String webUrl) => webUrl;
}

class _CacheEntry {
  final dynamic data;
  final DateTime expiresAt;
  _CacheEntry(this.data, this.expiresAt);
}
