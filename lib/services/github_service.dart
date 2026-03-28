import 'dart:convert';
import 'api_client.dart';

class GitHubService {
  final String token;
  late final Map<String, String> _headers;
  final Map<String, _CacheEntry> _cache = {};

  GitHubService({required this.token}) {
    _headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/vnd.github+json',
    };
  }

  Future<dynamic> _get(String url, String cacheKey, {Duration ttl = const Duration(minutes: 3)}) async {
    final cached = _cache[cacheKey];
    if (cached != null && DateTime.now().isBefore(cached.expiresAt)) return cached.data;

    final res = await ApiClient.get(url, headers: _headers);
    if (res.statusCode != 200) throw Exception('GitHub ${res.statusCode}: ${res.reasonPhrase}');
    final data = jsonDecode(res.body);
    _cache[cacheKey] = _CacheEntry(data, DateTime.now().add(ttl));
    return data;
  }

  void clearCache() => _cache.clear();

  Future<Map<String, dynamic>> getUser() async =>
      await _get('https://api.github.com/user', 'user', ttl: const Duration(minutes: 10));

  Future<List<dynamic>> getMyPRs() async {
    final user = await getUser();
    final q = Uri.encodeComponent('is:pr is:open author:${user['login']}');
    final data = await _get('https://api.github.com/search/issues?q=$q&per_page=30&sort=updated', 'my_prs');
    return data['items'] ?? [];
  }

  Future<List<dynamic>> getReviewRequests() async {
    final user = await getUser();
    final q = Uri.encodeComponent('is:pr is:open review-requested:${user['login']}');
    final data = await _get('https://api.github.com/search/issues?q=$q&per_page=30&sort=updated', 'review_reqs');
    return data['items'] ?? [];
  }

  Future<List<dynamic>> getAssignedIssues() async {
    final q = Uri.encodeComponent('is:issue is:open assignee:@me');
    final data = await _get('https://api.github.com/search/issues?q=$q&per_page=30&sort=updated', 'assigned');
    return data['items'] ?? [];
  }

  Future<List<dynamic>> getPRFiles(String owner, String repo, int number) async {
    final data = await _get(
      'https://api.github.com/repos/$owner/$repo/pulls/$number/files?per_page=100',
      'pr_files_${owner}_${repo}_$number',
      ttl: const Duration(minutes: 5),
    );
    return data is List ? data : [];
  }

  List<Map<String, String>> generateReviewSuggestions(List<dynamic> files) {
    final suggestions = <Map<String, String>>[];
    for (final f in files) {
      final filename = f['filename'] ?? '';
      final additions = f['additions'] ?? 0;
      final patch = f['patch'] ?? '';

      if (additions > 300) {
        suggestions.add({'file': filename, 'type': 'size', 'msg': 'Large change (+$additions lines) — consider splitting'});
      }
      if (patch.contains('TODO') || patch.contains('FIXME') || patch.contains('HACK')) {
        suggestions.add({'file': filename, 'type': 'todo', 'msg': 'Contains TODO/FIXME — address before merge?'});
      }
      if (patch.contains('console.log') || patch.contains('debugger') || patch.contains('print(')) {
        suggestions.add({'file': filename, 'type': 'debug', 'msg': 'Debug statements found — remove before merge'});
      }
      if (RegExp(r'\.(env|key|pem|secret)').hasMatch(filename)) {
        suggestions.add({'file': filename, 'type': 'security', 'msg': 'Sensitive file modified — verify no secrets exposed'});
      }
      if (RegExp(r'password|api[_-]?key', caseSensitive: false).hasMatch(patch)) {
        suggestions.add({'file': filename, 'type': 'security', 'msg': 'Possible credential in diff — double-check'});
      }
    }
    return suggestions;
  }
}

class _CacheEntry {
  final dynamic data;
  final DateTime expiresAt;
  _CacheEntry(this.data, this.expiresAt);
}
