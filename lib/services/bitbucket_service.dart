import 'dart:convert';
import 'api_client.dart';

class BitbucketService {
  final String workspace;
  final String email;
  final String token;
  late final Map<String, String> _headers;
  final Map<String, _CacheEntry> _cache = {};

  final List<String> targetRepos; // empty = all

  BitbucketService({required this.workspace, required this.email, required this.token, this.targetRepos = const []}) {
    _headers = {
      'Authorization': 'Basic ${base64Encode(utf8.encode('$email:$token'))}',
      'Accept': 'application/json',
    };
  }

  String get _base => 'https://api.bitbucket.org/2.0';

  Future<dynamic> _get(String url, String cacheKey, {Duration ttl = const Duration(minutes: 3)}) async {
    final cached = _cache[cacheKey];
    if (cached != null && DateTime.now().isBefore(cached.expiresAt)) return cached.data;

    final res = await ApiClient.get(url, headers: _headers);
    if (res.statusCode != 200) {
      String detail = res.reasonPhrase ?? '';
      try {
        final body = jsonDecode(res.body);
        detail = body['error']?['message'] ?? body['error']?['detail'] ?? detail;
      } catch (_) {}
      throw Exception('Bitbucket ${res.statusCode}: $detail');
    }
    final data = jsonDecode(res.body);
    _cache[cacheKey] = _CacheEntry(data, DateTime.now().add(ttl));
    return data;
  }

  void clearCache() => _cache.clear();

  /// Get all repos in the workspace that the token can access.
  Future<List<dynamic>> _getRepos() async {
    final data = await _get(
      '$_base/repositories/$workspace?pagelen=50&sort=-updated_on',
      'bb_repos',
      ttl: const Duration(minutes: 5),
    );
    return data['values'] ?? [];
  }

  Future<List<dynamic>> getAllOpenPRs() async {
    List<dynamic> repos;

    if (targetRepos.isNotEmpty) {
      // Only fetch the specific repos the user chose
      repos = targetRepos.map((slug) => {'slug': slug, 'full_name': '$workspace/$slug'}).toList();
    } else {
      repos = await _getRepos();
    }

    final allPRs = <dynamic>[];

    for (final repo in repos) {
      final slug = repo['slug'] ?? '';
      if (slug.isEmpty) continue;
      try {
        final prData = await _get(
          '$_base/repositories/$workspace/$slug/pullrequests?state=OPEN&pagelen=30',
          'bb_prs_$slug',
        );
        for (final pr in (prData['values'] ?? [])) {
          pr['_repo'] = repo['full_name'] ?? '$workspace/$slug';
          pr['_repo_slug'] = slug;
          allPRs.add(pr);
        }
      } catch (_) {
        // Skip repos we can't access
      }
    }
    return allPRs;
  }

  /// Since we can't identify the current user with workspace tokens,
  /// we return all open PRs and let the user see everything.
  Future<List<dynamic>> getMyPRs() async => getAllOpenPRs();

  /// Without user identity, return empty — PRs are all in getMyPRs.
  Future<List<dynamic>> getReviewRequests() async => [];

  Future<List<dynamic>> getRepoPRs(String repoSlug) async {
    final data = await _get(
      '$_base/repositories/$workspace/$repoSlug/pullrequests?state=OPEN&pagelen=30',
      'bb_repo_prs_$repoSlug',
    );
    return data['values'] ?? [];
  }

  Future<Map<String, dynamic>> getPRDetail(String repoSlug, int prId) async {
    return await _get(
      '$_base/repositories/$workspace/$repoSlug/pullrequests/$prId',
      'bb_pr_detail_${repoSlug}_$prId',
      ttl: const Duration(minutes: 5),
    );
  }

  String prUrl(String repoFullName, int prId) =>
      'https://bitbucket.org/$repoFullName/pull-requests/$prId';
}

class _CacheEntry {
  final dynamic data;
  final DateTime expiresAt;
  _CacheEntry(this.data, this.expiresAt);
}
