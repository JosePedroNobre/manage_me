import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// ── Service connection configs ─────────────────────────────────

class JiraConfig {
  String domain;
  String email;
  String token;
  JiraConfig({this.domain = '', this.email = '', this.token = ''});
  bool get isValid => domain.isNotEmpty && email.isNotEmpty && token.isNotEmpty;
  Map<String, dynamic> toJson() => {'domain': domain, 'email': email, 'token': token};
  factory JiraConfig.fromJson(Map<String, dynamic> j) => JiraConfig(domain: j['domain'] ?? '', email: j['email'] ?? '', token: j['token'] ?? '');
}

class GitHubConfig {
  String token;
  GitHubConfig({this.token = ''});
  bool get isValid => token.isNotEmpty;
  Map<String, dynamic> toJson() => {'token': token};
  factory GitHubConfig.fromJson(Map<String, dynamic> j) => GitHubConfig(token: j['token'] ?? '');
}

class GitLabConfig {
  String domain;
  String token;
  GitLabConfig({this.domain = 'gitlab.com', this.token = ''});
  bool get isValid => domain.isNotEmpty && token.isNotEmpty;
  Map<String, dynamic> toJson() => {'domain': domain, 'token': token};
  factory GitLabConfig.fromJson(Map<String, dynamic> j) => GitLabConfig(domain: j['domain'] ?? 'gitlab.com', token: j['token'] ?? '');
}

class BitbucketConfig {
  String workspace;
  String email;
  String token;
  String repos; // comma-separated repo slugs, empty = all
  BitbucketConfig({this.workspace = '', this.email = '', this.token = '', this.repos = ''});
  bool get isValid => workspace.isNotEmpty && token.isNotEmpty;
  List<String> get repoList => repos.isEmpty ? [] : repos.split(',').map((r) => r.trim()).where((r) => r.isNotEmpty).toList();
  Map<String, dynamic> toJson() => {'workspace': workspace, 'email': email, 'token': token, 'repos': repos};
  factory BitbucketConfig.fromJson(Map<String, dynamic> j) => BitbucketConfig(workspace: j['workspace'] ?? '', email: j['email'] ?? '', token: j['token'] ?? '', repos: j['repos'] ?? '');
}

// ── Team ──────────────────────────────────────────────────────

class Team {
  String name;
  String emoji;
  String claudeApiKey;
  String claudeProjectPath;
  JiraConfig? jira;
  GitHubConfig? github;
  GitLabConfig? gitlab;
  BitbucketConfig? bitbucket;

  Team({required this.name, this.emoji = '\u{1F4BC}', this.claudeApiKey = '', this.claudeProjectPath = '', this.jira, this.github, this.gitlab, this.bitbucket});

  bool get hasAnyService =>
      (jira?.isValid ?? false) ||
      (github?.isValid ?? false) ||
      (gitlab?.isValid ?? false) ||
      (bitbucket?.isValid ?? false);

  bool get hasClaude => claudeApiKey.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'name': name,
    'emoji': emoji,
    'claudeApiKey': claudeApiKey,
    'claudeProjectPath': claudeProjectPath,
    'jira': jira?.toJson(),
    'github': github?.toJson(),
    'gitlab': gitlab?.toJson(),
    'bitbucket': bitbucket?.toJson(),
  };

  factory Team.fromJson(Map<String, dynamic> j) => Team(
    name: j['name'] ?? '',
    emoji: j['emoji'] ?? '\u{1F4BC}',
    claudeApiKey: j['claudeApiKey'] ?? '',
    claudeProjectPath: j['claudeProjectPath'] ?? '',
    jira: j['jira'] != null ? JiraConfig.fromJson(j['jira']) : null,
    github: j['github'] != null ? GitHubConfig.fromJson(j['github']) : null,
    gitlab: j['gitlab'] != null ? GitLabConfig.fromJson(j['gitlab']) : null,
    bitbucket: j['bitbucket'] != null ? BitbucketConfig.fromJson(j['bitbucket']) : null,
  );
}

// ── All data ──────────────────────────────────────────────────

class AllConnections {
  List<Team> teams;

  AllConnections({List<Team>? teams}) : teams = teams ?? [];

  bool get hasAny => teams.any((t) => t.hasAnyService);

  Map<String, dynamic> toJson() => {'teams': teams.map((t) => t.toJson()).toList()};

  factory AllConnections.fromJson(Map<String, dynamic> json) {
    return AllConnections(
      teams: (json['teams'] as List?)?.map((j) => Team.fromJson(j)).toList(),
    );
  }

  // Migration from old multi-account format
  factory AllConnections.migrateFromLegacy(Map<String, dynamic> json) {
    final conns = AllConnections();
    // Old format had separate lists — group into a single "My Work" team
    final team = Team(name: 'My Work', emoji: '\u{1F4BC}');
    if (json['jira'] is List && (json['jira'] as List).isNotEmpty) {
      team.jira = JiraConfig.fromJson((json['jira'] as List).first);
    }
    if (json['github'] is List && (json['github'] as List).isNotEmpty) {
      team.github = GitHubConfig.fromJson((json['github'] as List).first);
    }
    if (json['gitlab'] is List && (json['gitlab'] as List).isNotEmpty) {
      team.gitlab = GitLabConfig.fromJson((json['gitlab'] as List).first);
    }
    if (json['bitbucket'] is List && (json['bitbucket'] as List).isNotEmpty) {
      team.bitbucket = BitbucketConfig.fromJson((json['bitbucket'] as List).first);
    }
    // Also handle old single-token format
    if ((json['jiraDomain'] ?? '').toString().isNotEmpty) {
      team.jira = JiraConfig(domain: json['jiraDomain'], email: json['jiraEmail'] ?? '', token: json['jiraToken'] ?? '');
    }
    if ((json['githubToken'] ?? '').toString().isNotEmpty) {
      team.github = GitHubConfig(token: json['githubToken']);
    }
    if (team.hasAnyService) conns.teams.add(team);
    return conns;
  }
}

// ── Storage service ───────────────────────────────────────────

class StorageService {
  static const _key = 'mm_teams_v3';
  static const _legacyKeys = ['mm_connections_v2', 'mm_tokens'];
  static const _settingsKey = 'mm_settings';
  final _secure = const FlutterSecureStorage();

  Future<void> saveConnections(AllConnections conns) async {
    await _secure.write(key: _key, value: jsonEncode(conns.toJson()));
  }

  Future<AllConnections> loadConnections() async {
    final raw = await _secure.read(key: _key);
    if (raw != null) {
      try { return AllConnections.fromJson(jsonDecode(raw)); } catch (_) {}
    }
    // Try legacy formats
    for (final legacyKey in _legacyKeys) {
      final legacy = await _secure.read(key: legacyKey);
      if (legacy != null) {
        try {
          final conns = AllConnections.migrateFromLegacy(jsonDecode(legacy));
          await saveConnections(conns);
          return conns;
        } catch (_) {}
      }
    }
    return AllConnections();
  }

  Future<void> clearAll() async {
    await _secure.deleteAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  Future<void> saveSetting(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_settingsKey}_$key', value);
  }

  Future<String?> loadSetting(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('${_settingsKey}_$key');
  }
}
