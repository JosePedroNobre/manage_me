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

  /// Get single MR details (includes diff_refs)
  Future<Map<String, dynamic>> getMR(int projectId, int iid) async {
    final data = await _get(
      'https://$domain/api/v4/projects/$projectId/merge_requests/$iid',
      'mr_${projectId}_$iid',
      ttl: const Duration(minutes: 3),
    );
    return data is Map<String, dynamic> ? data : {};
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

  /// Parse diff lines with both old and new line numbers.
  /// Returns list of {newLine, oldLine, added} for each valid line in the diff.
  static List<Map<String, dynamic>> _parseDiffLines(String diff) {
    final result = <Map<String, dynamic>>[];
    int oldLine = 0, newLine = 0;
    for (final l in diff.split('\n')) {
      final hunk = RegExp(r'^@@ -(\d+).*\+(\d+)').firstMatch(l);
      if (hunk != null) {
        oldLine = int.parse(hunk.group(1)!);
        newLine = int.parse(hunk.group(2)!);
        continue;
      }
      if (newLine == 0) continue;
      if (l.startsWith('-')) {
        // Deleted line — old side only
        oldLine++;
      } else if (l.startsWith('+')) {
        // Added line — new side only, use new_line
        result.add({'newLine': newLine, 'oldLine': null, 'added': true});
        newLine++;
      } else {
        // Context line — both sides
        result.add({'newLine': newLine, 'oldLine': oldLine, 'added': false});
        oldLine++;
        newLine++;
      }
    }
    return result;
  }

  /// Find the closest diff line to the target new-side line number.
  static Map<String, dynamic>? _findClosestLine(int target, List<Map<String, dynamic>> diffLines) {
    if (diffLines.isEmpty) return null;
    Map<String, dynamic> best = diffLines[0];
    int bestDist = (target - (best['newLine'] as int)).abs();
    for (final dl in diffLines) {
      final d = (target - (dl['newLine'] as int)).abs();
      if (d < bestDist) { best = dl; bestDist = d; }
    }
    return best;
  }

  /// Post inline discussions on an MR diff.
  Future<List<Map<String, dynamic>>> postMRInlineComments(int projectId, int iid, List<Map<String, dynamic>> comments, String headSha, String baseSha, String startSha) async {
    // Clear cache to get fresh changes
    _cache.remove('mr_changes_${projectId}_$iid');
    final changes = await getMRChanges(projectId, iid);

    // Build per-file diff line data with both old/new paths
    final fileData = <String, Map<String, dynamic>>{};
    for (final c in changes) {
      final newPath = c['new_path'] as String? ?? '';
      final oldPath = c['old_path'] as String? ?? newPath;
      final diff = c['diff'] as String? ?? '';
      if (newPath.isNotEmpty && diff.isNotEmpty) {
        fileData[newPath] = {
          'oldPath': oldPath,
          'newPath': newPath,
          'lines': _parseDiffLines(diff),
        };
      }
    }

    final results = <Map<String, dynamic>>[];
    for (final c in comments) {
      final rawPath = c['file'] as String? ?? '';
      var cleanPath = rawPath.replaceFirst(RegExp(r'^(\+\+\+|\-\-\-)\s*'), '').replaceFirst(RegExp(r'^[ab]/'), '').trim();

      // Try exact match, then fuzzy
      if (!fileData.containsKey(cleanPath)) {
        final match = fileData.keys.firstWhere(
          (p) => p.endsWith('/$cleanPath') || cleanPath.endsWith('/$p') || p.split('/').last == cleanPath.split('/').last,
          orElse: () => '',
        );
        if (match.isNotEmpty) cleanPath = match;
      }

      final fd = fileData[cleanPath];
      final requestedLine = (c['line'] as num?)?.toInt() ?? 0;

      if (fd != null) {
        final diffLines = fd['lines'] as List<Map<String, dynamic>>;
        final closest = _findClosestLine(requestedLine, diffLines);

        if (closest != null) {
          final position = <String, dynamic>{
            'position_type': 'text',
            'old_path': fd['oldPath'],
            'new_path': fd['newPath'],
            'head_sha': headSha,
            'base_sha': baseSha,
            'start_sha': startSha,
          };

          // Added lines: only new_line. Context lines: both old_line and new_line.
          if (closest['added'] == true) {
            position['new_line'] = closest['newLine'];
          } else {
            position['new_line'] = closest['newLine'];
            position['old_line'] = closest['oldLine'];
          }

          final res = await ApiClient.post(
            'https://$domain/api/v4/projects/$projectId/merge_requests/$iid/discussions',
            headers: _headers,
            body: jsonEncode({'body': c['comment'], 'position': position}),
          );

          if (res.statusCode == 201) {
            results.add({'ok': true});
            continue;
          }

          // Failed — fall back to note
          final fallback = await ApiClient.post(
            'https://$domain/api/v4/projects/$projectId/merge_requests/$iid/notes',
            headers: _headers,
            body: jsonEncode({'body': '`${fd['newPath']}:$requestedLine` — ${c['comment']}'}),
          );
          results.add({'ok': fallback.statusCode == 201, 'fallback': true, 'inline_error': res.body});
        } else {
          final fallback = await ApiClient.post(
            'https://$domain/api/v4/projects/$projectId/merge_requests/$iid/notes',
            headers: _headers,
            body: jsonEncode({'body': '`$cleanPath:$requestedLine` — ${c['comment']}'}),
          );
          results.add({'ok': fallback.statusCode == 201, 'fallback': true, 'inline_error': 'no diff lines parsed for $cleanPath'});
        }
      } else {
        final fallback = await ApiClient.post(
          'https://$domain/api/v4/projects/$projectId/merge_requests/$iid/notes',
          headers: _headers,
          body: jsonEncode({'body': '`$cleanPath:$requestedLine` — ${c['comment']}'}),
        );
        results.add({'ok': fallback.statusCode == 201, 'fallback': true, 'inline_error': 'file not found in diff. known: ${fileData.keys.join(", ")}'});
      }
    }
    return results;
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

  /// Get project board lists (columns) — returns label-based lists
  Future<List<dynamic>> getBoardLists(int projectId) async {
    try {
      // Get the project's boards
      final boards = await _get(
        'https://$domain/api/v4/projects/$projectId/boards',
        'boards_$projectId',
        ttl: const Duration(minutes: 10),
      );
      if (boards is! List || boards.isEmpty) return [];
      final boardId = boards[0]['id'];
      // Get the lists (columns) for the first board
      final lists = await _get(
        'https://$domain/api/v4/projects/$projectId/boards/$boardId/lists',
        'board_lists_$projectId',
        ttl: const Duration(minutes: 10),
      );
      return lists is List ? lists : [];
    } catch (_) {
      return [];
    }
  }

  /// Update issue labels
  Future<bool> updateIssueLabels(int projectId, int iid, List<String> labels) async {
    final res = await ApiClient.put(
      'https://$domain/api/v4/projects/$projectId/issues/$iid',
      headers: _headers,
      body: jsonEncode({'labels': labels.join(',')}),
    );
    return res.statusCode == 200;
  }

  /// Close or reopen an issue
  Future<bool> updateIssueState(int projectId, int iid, String stateEvent) async {
    final res = await ApiClient.put(
      'https://$domain/api/v4/projects/$projectId/issues/$iid',
      headers: _headers,
      body: jsonEncode({'state_event': stateEvent}),
    );
    return res.statusCode == 200;
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
