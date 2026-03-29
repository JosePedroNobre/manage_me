import 'package:flutter/material.dart';
import 'storage_service.dart';
import 'jira_service.dart';
import 'github_service.dart';
import 'gitlab_service.dart';
import 'bitbucket_service.dart';
import 'claude_service.dart';

/// Cache for AI results so we don't re-run on every click
class AICache {
  final Map<String, ImplementationPlan> plans = {};
  final Map<String, ClaudeReview> reviews = {};
}

class TeamData {
  final Team config;
  JiraService? jira;
  GitHubService? github;
  GitLabService? gitlab;
  BitbucketService? bitbucket;
  ClaudeService? claude;

  List<dynamic> jiraIssues = [];
  List<dynamic> jiraBoards = [];
  Map<String, dynamic>? jiraTeamWork;

  List<dynamic> ghMyPRs = [];
  List<dynamic> ghReviewReqs = [];
  List<dynamic> ghAssigned = [];

  List<dynamic> glMyMRs = [];
  List<dynamic> glReviews = [];
  List<dynamic> glAssigned = [];

  List<dynamic> bbPRs = [];
  final AICache aiCache = AICache();

  TeamData(this.config) {
    if (config.jira?.isValid ?? false) {
      final j = config.jira!;
      jira = JiraService(domain: j.domain, email: j.email, token: j.token);
    }
    if (config.github?.isValid ?? false) {
      github = GitHubService(token: config.github!.token);
    }
    if (config.gitlab?.isValid ?? false) {
      final g = config.gitlab!;
      gitlab = GitLabService(domain: g.domain, token: g.token);
    }
    if (config.bitbucket?.isValid ?? false) {
      final b = config.bitbucket!;
      bitbucket = BitbucketService(workspace: b.workspace, email: b.email, token: b.token, targetRepos: b.repoList);
    }
    if (config.hasClaude) {
      claude = ClaudeService(apiKey: config.claudeApiKey, projectPath: config.claudeProjectPath);
    }
  }

  int get totalItems => jiraIssues.length + ghMyPRs.length + ghReviewReqs.length + ghAssigned.length + glMyMRs.length + glReviews.length + glAssigned.length + bbPRs.length;
  int get reviewCount => ghReviewReqs.length + glReviews.length;
}

class AppState extends ChangeNotifier {
  final StorageService _storage = StorageService();
  AllConnections connections = AllConnections();

  List<TeamData> teams = [];
  int selectedTeamIndex = 0;
  bool isLoading = false;
  String? error;
  String? selectedBoardKey;

  TeamData? get currentTeam => teams.isNotEmpty && selectedTeamIndex < teams.length ? teams[selectedTeamIndex] : null;

  Future<void> init() async {
    connections = await _storage.loadConnections();
    selectedBoardKey = await _storage.loadSetting('jiraBoardKey');
    final savedTeamIdx = await _storage.loadSetting('selectedTeam');
    if (savedTeamIdx != null) selectedTeamIndex = int.tryParse(savedTeamIdx) ?? 0;
    _buildTeams();
    notifyListeners();
  }

  void _buildTeams() {
    teams = connections.teams.where((t) => t.hasAnyService).map((t) => TeamData(t)).toList();
    if (selectedTeamIndex >= teams.length) selectedTeamIndex = 0;
  }

  Future<void> saveConnections(AllConnections conns) async {
    connections = conns;
    await _storage.saveConnections(conns);
    _buildTeams();
    notifyListeners();
  }

  void selectTeam(int idx) {
    selectedTeamIndex = idx;
    _storage.saveSetting('selectedTeam', '$idx');
    notifyListeners();
    loadCurrentTeam();
  }

  Future<void> loadAllData() async {
    isLoading = true;
    error = null;
    notifyListeners();
    await Future.wait(teams.map(_loadTeamData));
    isLoading = false;
    notifyListeners();
  }

  Future<void> loadCurrentTeam() async {
    if (currentTeam == null) return;
    isLoading = true;
    error = null;
    notifyListeners();
    await _loadTeamData(currentTeam!);
    isLoading = false;
    notifyListeners();
  }

  Future<void> refreshAll() async {
    if (currentTeam == null) return;
    currentTeam!.jira?.clearCache();
    currentTeam!.github?.clearCache();
    currentTeam!.gitlab?.clearCache();
    currentTeam!.bitbucket?.clearCache();
    await loadCurrentTeam();
  }

  Future<void> _loadTeamData(TeamData td) async {
    final futures = <Future>[];
    if (td.jira != null) futures.add(_loadJira(td));
    if (td.github != null) futures.add(_loadGitHub(td));
    if (td.gitlab != null) futures.add(_loadGitLab(td));
    if (td.bitbucket != null) futures.add(_loadBitbucket(td));
    await Future.wait(futures);
  }

  Future<void> _loadJira(TeamData td) async {
    // Load issues (main) — always works
    try {
      td.jiraIssues = await td.jira!.getMyIssues();
    } catch (e) { _addError('Jira issues (${td.config.name}): $e'); }

    // Load boards (agile API) — may 401 if no agile access, non-blocking
    try {
      td.jiraBoards = await td.jira!.getBoards();
      if (selectedBoardKey != null) await loadJiraTeamByKey(selectedBoardKey!, td);
    } catch (_) { /* Agile API not available — skip silently */ }
  }

  Future<void> _loadGitHub(TeamData td) async {
    try {
      final results = await Future.wait([td.github!.getMyPRs(), td.github!.getReviewRequests(), td.github!.getAssignedIssues()]);
      td.ghMyPRs = results[0]; td.ghReviewReqs = results[1]; td.ghAssigned = results[2];
    } catch (e) { _addError('GitHub (${td.config.name}): $e'); }
  }

  Future<void> _loadGitLab(TeamData td) async {
    try {
      final results = await Future.wait([td.gitlab!.getMyMRs(), td.gitlab!.getReviewRequests(), td.gitlab!.getAssignedIssues()]);
      td.glMyMRs = results[0];
      // Deduplicate: remove from assigned any MRs that are already in "my MRs"
      final myIds = td.glMyMRs.map((m) => m['id']).toSet();
      td.glReviews = results[1].where((m) => !myIds.contains(m['id'])).toList();
      td.glAssigned = results[2];
    } catch (e) { _addError('GitLab (${td.config.name}): $e'); }
  }

  Future<void> _loadBitbucket(TeamData td) async {
    try {
      td.bbPRs = await td.bitbucket!.getAllOpenPRs();
    } catch (e) { _addError('Bitbucket (${td.config.name}): $e'); }
  }

  Future<void> selectBoard(String key) async {
    selectedBoardKey = key;
    await _storage.saveSetting('jiraBoardKey', key);
    notifyListeners();
    if (currentTeam != null) await loadJiraTeamByKey(key, currentTeam!);
  }

  Future<void> loadJiraTeamByKey(String key, TeamData td) async {
    final parts = key.split(':');
    if (parts.length != 2) return;
    final boardId = int.tryParse(parts[1]);
    if (boardId == null || td.jira == null) return;
    try {
      td.jiraTeamWork = await td.jira!.getTeamWork(boardId);
      notifyListeners();
    } catch (e) { _addError('Board: $e'); notifyListeners(); }
  }

  void _addError(String msg) { error = error != null ? '$error\n$msg' : msg; }

  Future<void> clearAll() async {
    await _storage.clearAll();
    connections = AllConnections();
    teams = [];
    selectedTeamIndex = 0;
    notifyListeners();
  }

  // Computed for current team
  int get totalTasks => currentTeam == null ? 0 : currentTeam!.jiraIssues.length + currentTeam!.ghAssigned.length + currentTeam!.glAssigned.length;
  int get totalPRs => currentTeam == null ? 0 : currentTeam!.ghMyPRs.length + currentTeam!.glMyMRs.length + currentTeam!.bbPRs.length;
  int get totalReviews => currentTeam == null ? 0 : currentTeam!.ghReviewReqs.length + currentTeam!.glReviews.length;
}
