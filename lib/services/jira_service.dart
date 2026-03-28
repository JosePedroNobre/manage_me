import 'dart:convert';
import 'api_client.dart';

class JiraService {
  final String domain;
  final String email;
  final String token;
  late final Map<String, String> _headers;
  final Map<String, _CacheEntry> _cache = {};

  JiraService({required this.domain, required this.email, required this.token}) {
    _headers = {
      'Authorization': 'Basic ${base64Encode(utf8.encode('$email:$token'))}',
      'Accept': 'application/json',
    };
  }

  String get _base => 'https://$domain/rest/api/3';
  String get _agileBase => 'https://$domain/rest/agile/1.0';

  Future<dynamic> _get(String url, String cacheKey, {Duration ttl = const Duration(minutes: 5)}) async {
    final cached = _cache[cacheKey];
    if (cached != null && DateTime.now().isBefore(cached.expiresAt)) return cached.data;

    final res = await ApiClient.get(url, headers: _headers);
    if (res.statusCode != 200) {
      String detail = res.reasonPhrase ?? '';
      try {
        final body = jsonDecode(res.body);
        detail = body['errorMessages']?.join(', ') ?? body['message'] ?? detail;
      } catch (_) {}
      throw Exception('Jira ${res.statusCode}: $detail');
    }
    final data = jsonDecode(res.body);
    _cache[cacheKey] = _CacheEntry(data, DateTime.now().add(ttl));
    return data;
  }

  void clearCache() => _cache.clear();

  Future<Map<String, dynamic>> getIssue(String key) async =>
      await _get('$_base/issue/$key?fields=summary,description,status,priority,issuetype,assignee,project,updated,created,reporter,attachment', 'issue_$key', ttl: const Duration(minutes: 5));

  Future<List<dynamic>> getTransitions(String key) async {
    final data = await _get('$_base/issue/$key/transitions', 'transitions_$key', ttl: const Duration(minutes: 1));
    return data['transitions'] ?? [];
  }

  Future<void> transitionIssue(String key, String transitionId) async {
    final res = await ApiClient.post('$_base/issue/$key/transitions', headers: _headers, body: '{"transition":{"id":"$transitionId"}}');
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw Exception('Failed to transition: ${res.statusCode}');
    }
    // Clear cache so next fetch gets new status
    _cache.remove('issue_$key');
    _cache.remove('my_issues');
    _cache.remove('transitions_$key');
  }

  Future<Map<String, dynamic>> getMyself() async =>
      await _get('$_base/myself', 'myself', ttl: const Duration(minutes: 10));

  Future<List<dynamic>> getBoards() async {
    final data = await _get('$_agileBase/board?maxResults=50', 'boards', ttl: const Duration(minutes: 10));
    return data['values'] ?? [];
  }

  Future<List<dynamic>> getBoardSprints(int boardId) async {
    final data = await _get(
      '$_agileBase/board/$boardId/sprint?state=active&maxResults=5',
      'sprints_$boardId',
    );
    return data['values'] ?? [];
  }

  Future<List<dynamic>> getSprintIssues(int sprintId) async {
    final data = await _get(
      '$_agileBase/sprint/$sprintId/issue?maxResults=100&fields=summary,status,assignee,priority,issuetype,updated',
      'sprint_issues_$sprintId',
      ttl: const Duration(minutes: 3),
    );
    return data['issues'] ?? [];
  }

  Future<List<dynamic>> getMyIssues() async {
    final jql = Uri.encodeComponent('assignee=currentUser() AND statusCategory in ("To Do", "In Progress") ORDER BY priority DESC, updated DESC');
    final fields = Uri.encodeComponent('summary,status,priority,issuetype,project,updated');
    final data = await _get(
      '$_base/search/jql?jql=$jql&maxResults=50&fields=$fields',
      'my_issues',
      ttl: const Duration(minutes: 3),
    );
    return data['issues'] ?? [];
  }

  Future<Map<String, dynamic>> getTeamWork(int boardId) async {
    final sprints = await getBoardSprints(boardId);
    if (sprints.isEmpty) return {'sprint': 'No active sprint', 'team': {}};

    final sprint = sprints.first;
    final issues = await getSprintIssues(sprint['id']);

    final Map<String, Map<String, dynamic>> grouped = {};
    for (final issue in issues) {
      final fields = issue['fields'] ?? {};
      final assignee = fields['assignee'];
      final name = assignee?['displayName'] ?? 'Unassigned';
      final avatar = assignee?['avatarUrls']?['32x32'] ?? '';

      grouped.putIfAbsent(name, () => {'avatar': avatar, 'issues': []});
      (grouped[name]!['issues'] as List).add({
        'key': issue['key'],
        'summary': fields['summary'] ?? '',
        'status': fields['status']?['name'] ?? '',
        'statusCategory': fields['status']?['statusCategory']?['key'] ?? '',
        'priority': fields['priority']?['name'] ?? '',
        'type': fields['issuetype']?['name'] ?? '',
        'url': 'https://$domain/browse/${issue['key']}',
      });
    }

    return {'sprint': sprint['name'] ?? '', 'team': grouped};
  }

  String issueUrl(String key) => 'https://$domain/browse/$key';
}

class _CacheEntry {
  final dynamic data;
  final DateTime expiresAt;
  _CacheEntry(this.data, this.expiresAt);
}
