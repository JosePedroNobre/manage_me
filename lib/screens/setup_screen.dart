import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_state.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late AllConnections _conns;
  int _editingTeamIndex = -1; // -1 = team list view
  final Map<String, TextEditingController> _ctrls = {};

  final _emojis = ['\u{1F4BC}', '\u{1F680}', '\u{1F3AF}', '\u{2B50}', '\u{1F527}', '\u{1F4A1}', '\u{1F30D}', '\u{1F3E2}', '\u{1F916}', '\u{1F525}'];

  @override
  void initState() {
    super.initState();
    final src = context.read<AppState>().connections;
    _conns = AllConnections.fromJson(src.toJson());
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) c.dispose();
    super.dispose();
  }

  TextEditingController _ctrl(String key, String initial) =>
      _ctrls.putIfAbsent(key, () => TextEditingController(text: initial));

  void _syncTeam(int idx) {
    final t = _conns.teams[idx];
    t.name = _ctrls['t${idx}_name']?.text ?? t.name;
    // Jira
    if (t.jira != null) {
      t.jira!.domain = _ctrls['t${idx}_jira_domain']?.text ?? t.jira!.domain;
      t.jira!.email = _ctrls['t${idx}_jira_email']?.text ?? t.jira!.email;
      t.jira!.token = _ctrls['t${idx}_jira_token']?.text ?? t.jira!.token;
    }
    if (t.github != null) {
      t.github!.token = _ctrls['t${idx}_gh_token']?.text ?? t.github!.token;
    }
    if (t.gitlab != null) {
      t.gitlab!.domain = _ctrls['t${idx}_gl_domain']?.text ?? t.gitlab!.domain;
      t.gitlab!.token = _ctrls['t${idx}_gl_token']?.text ?? t.gitlab!.token;
    }
    if (t.bitbucket != null) {
      t.bitbucket!.workspace = _ctrls['t${idx}_bb_workspace']?.text ?? t.bitbucket!.workspace;
      t.bitbucket!.email = _ctrls['t${idx}_bb_email']?.text ?? t.bitbucket!.email;
      t.bitbucket!.token = _ctrls['t${idx}_bb_token']?.text ?? t.bitbucket!.token;
      t.bitbucket!.repos = _ctrls['t${idx}_bb_repos']?.text ?? t.bitbucket!.repos;
    }
    t.claudeApiKey = _ctrls['t${idx}_claude_key']?.text ?? t.claudeApiKey;
    t.claudeProjectPath = _ctrls['t${idx}_claude_path']?.text ?? t.claudeProjectPath;
    // Clean up empty services
    if (t.jira != null && !t.jira!.isValid) t.jira = null;
    if (t.github != null && !t.github!.isValid) t.github = null;
    if (t.gitlab != null && !t.gitlab!.isValid) t.gitlab = null;
    if (t.bitbucket != null && !t.bitbucket!.isValid) t.bitbucket = null;
  }

  Future<void> _save() async {
    for (int i = 0; i < _conns.teams.length; i++) _syncTeam(i);
    _conns.teams.removeWhere((t) => t.name.isEmpty || !t.hasAnyService);
    if (!_conns.hasAny) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one team with a service connected'), backgroundColor: AppColors.red),
      );
      return;
    }
    await context.read<AppState>().saveConnections(_conns);
    if (mounted) Navigator.of(context).pushReplacementNamed('/dashboard');
  }

  void _addTeam() {
    setState(() {
      _conns.teams.add(Team(name: '', emoji: _emojis[_conns.teams.length % _emojis.length]));
      _editingTeamIndex = _conns.teams.length - 1;
    });
  }

  void _removeTeam(int idx) {
    _ctrls.removeWhere((k, v) { if (k.startsWith('t${idx}_')) { v.dispose(); return true; } return false; });
    setState(() { _conns.teams.removeAt(idx); _editingTeamIndex = -1; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: _editingTeamIndex >= 0 ? _buildTeamEditor(_editingTeamIndex) : _buildTeamList(),
            ),
          ),
        ),
      ),
    );
  }

  // ── STEP 1: Team list ──────────────────────────────────────

  Widget _buildTeamList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _logo(),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.accentSurface, borderRadius: BorderRadius.circular(10)),
          child: const Row(children: [
            Icon(Icons.groups, size: 18, color: AppColors.accent),
            SizedBox(width: 8),
            Expanded(child: Text('Create a team for each job or project, then add your tools inside.',
              style: TextStyle(fontSize: 13, color: AppColors.accent, fontWeight: FontWeight.w500))),
          ]),
        ),
        const SizedBox(height: 24),

        // Existing teams
        ..._conns.teams.asMap().entries.map((e) => _teamCard(e.key, e.value)),

        const SizedBox(height: 12),
        // Add team button
        GestureDetector(
          onTap: _addTeam,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.accent, style: BorderStyle.solid),
              borderRadius: BorderRadius.circular(14),
              color: AppColors.accentSurface,
            ),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add_circle_outline, size: 20, color: AppColors.accent),
              SizedBox(width: 8),
              Text('Add a team', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.accent)),
            ]),
          ),
        ),

        if (_conns.teams.any((t) => t.hasAnyService)) ...[
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.rocket_launch, size: 18),
              label: const Text('Launch Dashboard'),
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _teamCard(int idx, Team team) {
    _syncTeam(idx); // ensure synced
    final services = <String>[];
    if (team.jira?.isValid ?? false) services.add('Jira');
    if (team.github?.isValid ?? false) services.add('GitHub');
    if (team.gitlab?.isValid ?? false) services.add('GitLab');
    if (team.bitbucket?.isValid ?? false) services.add('Bitbucket');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.bg1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: team.hasAnyService ? AppColors.green.withAlpha(80) : AppColors.borderSubtle),
        boxShadow: [BoxShadow(color: AppColors.border.withAlpha(30), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: InkWell(
        onTap: () => setState(() => _editingTeamIndex = idx),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Text(team.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(team.name.isEmpty ? 'New team' : team.name,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: team.name.isEmpty ? AppColors.text3 : AppColors.text0)),
              const SizedBox(height: 2),
              if (services.isNotEmpty)
                Text(services.join(' \u00B7 '), style: const TextStyle(fontSize: 12, color: AppColors.green, fontWeight: FontWeight.w500))
              else
                const Text('No services connected yet', style: TextStyle(fontSize: 12, color: AppColors.text3)),
            ])),
            const Icon(Icons.chevron_right, color: AppColors.text3, size: 20),
          ]),
        ),
      ),
    );
  }

  // ── STEP 2: Edit team ──────────────────────────────────────

  Widget _buildTeamEditor(int idx) {
    final t = _conns.teams[idx];
    final prefix = 't${idx}_';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back button
        GestureDetector(
          onTap: () { _syncTeam(idx); setState(() => _editingTeamIndex = -1); },
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.arrow_back, size: 18, color: AppColors.accent),
            SizedBox(width: 6),
            Text('Back to teams', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.accent)),
          ]),
        ),
        const SizedBox(height: 20),

        // Team name + emoji
        Row(children: [
          // Emoji picker
          GestureDetector(
            onTap: () => _pickEmoji(idx),
            child: Container(
              width: 52, height: 52,
              decoration: BoxDecoration(color: AppColors.bg2, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
              alignment: Alignment.center,
              child: Text(t.emoji, style: const TextStyle(fontSize: 26)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: TextField(
            controller: _ctrl('${prefix}name', t.name),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text0),
            decoration: const InputDecoration(hintText: 'Team name (e.g. Vinturas, Freelance)', border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false),
          )),
        ]),
        const SizedBox(height: 24),

        const Text('CONNECT SERVICES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.text3, letterSpacing: 1)),
        const SizedBox(height: 12),

        // Jira
        _serviceToggle(
          emoji: '\u{1F3AF}', title: 'Jira', enabled: t.jira != null,
          onToggle: (v) => setState(() => t.jira = v ? JiraConfig() : null),
          helpUrl: 'https://id.atlassian.com/manage-profile/security/api-tokens',
          fields: t.jira != null ? Column(children: [
            _input('${prefix}jira_domain', t.jira!.domain, 'Domain', hint: 'e.g. yourteam.atlassian.net'),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _input('${prefix}jira_email', t.jira!.email, 'Email', hint: 'e.g. john@company.com')),
              const SizedBox(width: 10),
              Expanded(child: _input('${prefix}jira_token', t.jira!.token, 'API Token', hint: 'Atlassian API token', obscure: true)),
            ]),
          ]) : null,
        ),
        const SizedBox(height: 10),

        // GitHub
        _serviceToggle(
          emoji: '\u{1F4BB}', title: 'GitHub', enabled: t.github != null,
          onToggle: (v) => setState(() => t.github = v ? GitHubConfig() : null),
          helpUrl: 'https://github.com/settings/tokens?type=beta',
          fields: t.github != null ? Column(children: [
            _input('${prefix}gh_token', t.github!.token, 'Token', hint: 'ghp_... or github_pat_...', obscure: true),
          ]) : null,
        ),
        const SizedBox(height: 10),

        // GitLab
        _serviceToggle(
          emoji: '\u{1F98A}', title: 'GitLab', enabled: t.gitlab != null,
          onToggle: (v) => setState(() => t.gitlab = v ? GitLabConfig() : null),
          helpUrl: 'https://gitlab.com/-/user_settings/personal_access_tokens',
          fields: t.gitlab != null ? Column(children: [
            Row(children: [
              Expanded(child: _input('${prefix}gl_domain', t.gitlab!.domain, 'Domain', hint: 'e.g. gitlab.com')),
              const SizedBox(width: 10),
              Expanded(child: _input('${prefix}gl_token', t.gitlab!.token, 'Token', hint: 'glpat-...', obscure: true)),
            ]),
          ]) : null,
        ),
        const SizedBox(height: 10),

        // Bitbucket
        _serviceToggle(
          emoji: '\u{1F4E6}', title: 'Bitbucket', enabled: t.bitbucket != null,
          onToggle: (v) => setState(() => t.bitbucket = v ? BitbucketConfig() : null),
          helpUrl: 'https://id.atlassian.com/manage-profile/security/api-tokens',
          fields: t.bitbucket != null ? Column(children: [
            _input('${prefix}bb_workspace', t.bitbucket!.workspace, 'Workspace slug', hint: 'e.g. vinturas'),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _input('${prefix}bb_email', t.bitbucket!.email, 'Atlassian email', hint: 'e.g. john@company.com')),
              const SizedBox(width: 10),
              Expanded(child: _input('${prefix}bb_token', t.bitbucket!.token, 'API Token', hint: 'Same as Jira token', obscure: true)),
            ]),
            const SizedBox(height: 10),
            _input('${prefix}bb_repos', t.bitbucket!.repos, 'Repos to track', hint: 'e.g. my-app, api — empty = all repos'),
          ]) : null,
        ),

        const SizedBox(height: 10),

        // Claude AI Review
        Container(
          decoration: BoxDecoration(
            color: AppColors.bg1,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.claudeApiKey == 'enabled' ? AppColors.accent.withAlpha(60) : AppColors.borderSubtle),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 0),
              child: Row(children: [
                const Text('\u{1F916}', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                const Expanded(child: Text('Claude AI Review', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text0))),
                Switch(
                  value: t.claudeApiKey == 'enabled',
                  onChanged: (v) => setState(() => t.claudeApiKey = v ? 'enabled' : ''),
                  activeColor: AppColors.accent,
                ),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text('AI-powered code reviews on your PRs, posted under your name.', style: TextStyle(fontSize: 12, color: AppColors.text2)),
            ),
            if (t.claudeApiKey == 'enabled') ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Row(children: [
                  Expanded(child: _input('${prefix}claude_path', t.claudeProjectPath, 'Project path', hint: 'e.g. /Users/nobre/Desktop/my-project')),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _showFolderPicker(context, '${prefix}claude_path', t),
                    icon: const Icon(Icons.folder_open, color: AppColors.accent),
                    tooltip: 'Browse folders',
                  ),
                ]),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.accentSurface, borderRadius: BorderRadius.circular(10)),
                child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.check_circle, size: 14, color: AppColors.accent),
                    SizedBox(width: 6),
                    Text('Uses your Claude Code subscription', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent)),
                  ]),
                  SizedBox(height: 6),
                  Text('Claude runs from your project directory so it can see your actual codebase, file structure, and existing code.',
                    style: TextStyle(fontSize: 11, color: AppColors.text1, height: 1.5)),
                  SizedBox(height: 8),
                  Text('Start the bridge with: python3 claude_bridge.py\nOr double-click start.command',
                    style: TextStyle(fontSize: 10, color: AppColors.text3, fontStyle: FontStyle.italic)),
                ]),
              ),
            ],
          ]),
        ),

        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () { _syncTeam(idx); setState(() => _editingTeamIndex = -1); },
            child: const Text('Done'),
          )),
          const SizedBox(width: 10),
          TextButton(
            onPressed: () => _removeTeam(idx),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Delete team'),
          ),
        ]),
      ],
    );
  }

  // ── Service toggle card ────────────────────────────────────

  Widget _serviceToggle({
    required String emoji,
    required String title,
    required bool enabled,
    required ValueChanged<bool> onToggle,
    required String helpUrl,
    Widget? fields,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: enabled ? AppColors.accent.withAlpha(60) : AppColors.borderSubtle),
      ),
      child: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(14, 10, 10, fields != null ? 0 : 10),
          child: Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text0))),
            GestureDetector(
              onTap: () => launchUrl(Uri.parse(helpUrl), mode: LaunchMode.externalApplication),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.accentSurface, borderRadius: BorderRadius.circular(6)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.open_in_new, size: 11, color: AppColors.accent),
                  SizedBox(width: 3),
                  Text('Get token', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.accent)),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            Switch(value: enabled, onChanged: onToggle, activeColor: AppColors.accent),
          ]),
        ),
        if (fields != null) Padding(padding: const EdgeInsets.fromLTRB(14, 4, 14, 14), child: fields),
      ]),
    );
  }

  // ── Emoji picker ───────────────────────────────────────────

  void _pickEmoji(int teamIdx) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bg1,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 12, runSpacing: 12,
          children: ['\u{1F4BC}', '\u{1F680}', '\u{1F3AF}', '\u{2B50}', '\u{1F527}', '\u{1F4A1}', '\u{1F30D}', '\u{1F3E2}', '\u{1F916}', '\u{1F525}', '\u{1F3AE}', '\u{1F4C8}', '\u{2764}', '\u{1F48E}', '\u{1F33F}', '\u{26A1}', '\u{1F3B5}', '\u{1F6E0}', '\u{1F4DA}', '\u{1F3D7}']
            .map((e) => GestureDetector(
              onTap: () { setState(() => _conns.teams[teamIdx].emoji = e); Navigator.pop(context); },
              child: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(color: AppColors.bg2, borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: Text(e, style: const TextStyle(fontSize: 24)),
              ),
            )).toList(),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────

  Future<void> _showFolderPicker(BuildContext context, String ctrlKey, Team team) async {
    String currentPath = _ctrls[ctrlKey]?.text ?? '';
    if (currentPath.isEmpty) currentPath = '/Users';

    final result = await showDialog<String>(
      context: context,
      builder: (_) => _FolderPickerDialog(initialPath: currentPath),
    );

    if (result != null) {
      setState(() {
        _ctrl(ctrlKey, result).text = result;
        team.claudeProjectPath = result;
      });
    }
  }

  Widget _input(String key, String initial, String label, {String hint = '', bool obscure = false}) {
    return TextField(
      controller: _ctrl(key, initial),
      obscureText: obscure,
      style: const TextStyle(fontSize: 14, color: AppColors.text0),
      decoration: InputDecoration(labelText: label, hintText: hint),
    );
  }

  Widget _logo() {
    return Row(children: [
      Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.accent, AppColors.accentLight]),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: const Text('M', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
      ),
      const SizedBox(width: 12),
      const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ManageMe', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.text0)),
        Text('Your teams & tools', style: TextStyle(fontSize: 14, color: AppColors.text3)),
      ]),
    ]);
  }
}

// ── Folder Picker Dialog ──────────────────────────────────────

class _FolderPickerDialog extends StatefulWidget {
  final String initialPath;
  const _FolderPickerDialog({required this.initialPath});
  @override
  State<_FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<_FolderPickerDialog> {
  String _current = '';
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _browse(widget.initialPath);
  }

  Future<void> _browse(String path) async {
    setState(() { _loading = true; _error = null; });
    try {
      final encoded = Uri.encodeComponent(path);
      final res = await http.get(Uri.parse('http://localhost:9091/browse?path=$encoded'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _current = data['current'] ?? path;
          _entries = List<Map<String, dynamic>>.from(data['entries'] ?? []);
          _loading = false;
        });
      } else {
        setState(() { _error = 'Failed to browse'; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = 'Bridge not running? $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.bg1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.border)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 500),
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Select project folder', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text0)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: AppColors.bg0, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                child: Text(_current, style: const TextStyle(fontSize: 12, color: AppColors.text2, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
          const Divider(height: 1, color: AppColors.borderSubtle),
          // Folder list
          Expanded(
            child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
              : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 13)))
                : ListView.builder(
                    itemCount: _entries.length,
                    itemBuilder: (_, i) {
                      final entry = _entries[i];
                      final name = entry['name'] ?? '';
                      final path = entry['path'] ?? '';
                      final isParent = name == '..';
                      return ListTile(
                        leading: Icon(isParent ? Icons.arrow_upward : Icons.folder, size: 20, color: isParent ? AppColors.text3 : AppColors.accent),
                        title: Text(name, style: TextStyle(fontSize: 14, color: isParent ? AppColors.text3 : AppColors.text0, fontWeight: isParent ? FontWeight.w400 : FontWeight.w500)),
                        dense: true,
                        onTap: () => _browse(path),
                      );
                    },
                  ),
          ),
          const Divider(height: 1, color: AppColors.borderSubtle),
          // Actions
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, _current),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Select this folder'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
