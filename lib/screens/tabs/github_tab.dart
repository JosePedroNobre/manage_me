import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/detail_dialog.dart';

class GitHubTab extends StatelessWidget {
  const GitHubTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, _) {
      final td = state.currentTeam;
      if (td == null) return const SizedBox.shrink();
      return ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          StatCard(value: '${td.ghMyPRs.length}', label: 'My PRs'),
          const SizedBox(width: 10),
          StatCard(value: '${td.ghReviewReqs.length}', label: 'Reviews'),
          const SizedBox(width: 10),
          StatCard(value: '${td.ghAssigned.length}', label: 'Issues'),
        ]),
        const SizedBox(height: 24),
        if (td.ghReviewReqs.isNotEmpty) ...[const SectionTitle('Review Requests'), ...td.ghReviewReqs.map((pr) => _prCard(context, pr, td, showAnalyze: true))],
        if (td.ghMyPRs.isNotEmpty) ...[const SectionTitle('My Pull Requests'), ...td.ghMyPRs.map((pr) => _prCard(context, pr, td, showAnalyze: true))],
        if (td.ghAssigned.isNotEmpty) ...[const SectionTitle('Assigned Issues'), ...td.ghAssigned.map((i) => _issueCard(context, i))],
        if (td.ghReviewReqs.isEmpty && td.ghMyPRs.isEmpty && td.ghAssigned.isEmpty) const EmptyState(icon: '\u{1F389}', message: 'Nothing on your plate'),
      ]);
    });
  }

  Widget _prCard(BuildContext context, dynamic pr, TeamData td, {bool showAnalyze = false}) {
    final repo = (pr['repository_url'] ?? '').toString().split('/').reversed.take(2).toList().reversed.join('/');
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Card(child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showPRDetail(context, pr),
      child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const ServiceIcon(label: '\u{2693}', bg: AppColors.accentSurface, fg: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('#${pr['number']} ${pr['title'] ?? ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text0), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 4, children: [
              Text(repo, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
              Text(timeAgo(pr['updated_at']), style: const TextStyle(fontSize: 12, color: AppColors.text3)),
              if (pr['draft'] == true) const StatusPill(label: 'Draft', category: 'todo'),
            ]),
          ])),
          const Icon(Icons.chevron_right, size: 18, color: AppColors.text3),
        ]),
        if (showAnalyze) ...[const SizedBox(height: 10), Row(children: [
          OutlinedButton.icon(
            onPressed: () => _analyzePR(context, pr, td),
            icon: const Icon(Icons.search, size: 16), label: const Text('Analyze PR'),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          if (td.claude != null) ...[const SizedBox(width: 8), ElevatedButton.icon(
            onPressed: () => _aiReview(context, pr, td),
            icon: const Icon(Icons.smart_toy, size: 16), label: const Text('AI Review'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          )],
        ])],
      ])),
    )));
  }

  Widget _issueCard(BuildContext context, dynamic issue) {
    final repo = (issue['repository_url'] ?? '').toString().split('/').reversed.take(2).toList().reversed.join('/');
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: IssueCard(
      icon: const ServiceIcon(label: '!', bg: AppColors.greenSoft, fg: AppColors.green),
      title: '#${issue['number']} ${issue['title'] ?? ''}',
      onTap: () => _showIssueDetail(context, issue),
      meta: [Text(repo, style: const TextStyle(fontSize: 12, color: AppColors.text2)), Text(timeAgo(issue['updated_at']), style: const TextStyle(fontSize: 12, color: AppColors.text3))],
    ));
  }

  void _showPRDetail(BuildContext context, dynamic pr) {
    final repo = (pr['repository_url'] ?? '').toString().split('/').reversed.take(2).toList().reversed.join('/');
    final labels = (pr['labels'] ?? []) as List;
    DetailDialog.show(context, serviceLabel: 'GitHub', accentColor: AppColors.accent, title: '#${pr['number']} ${pr['title'] ?? ''}', subtitle: repo, url: pr['html_url'], description: pr['body'] ?? '',
      meta: [
        if (pr['state'] != null) DetailMeta(label: 'State', widget: StatusPill(label: pr['state'], category: pr['state'] == 'open' ? 'progress' : 'done')),
        if (pr['draft'] == true) const DetailMeta(label: 'Draft', widget: StatusPill(label: 'Draft', category: 'todo')),
        DetailMeta(label: 'Author', value: pr['user']?['login'] ?? ''),
        DetailMeta(label: 'Updated', value: timeAgo(pr['updated_at'])),
        if (labels.isNotEmpty) DetailMeta(label: 'Labels', value: labels.map((l) => l['name']).join(', ')),
      ]);
  }

  void _showIssueDetail(BuildContext context, dynamic issue) {
    final repo = (issue['repository_url'] ?? '').toString().split('/').reversed.take(2).toList().reversed.join('/');
    DetailDialog.show(context, serviceLabel: 'GitHub', accentColor: AppColors.green, title: '#${issue['number']} ${issue['title'] ?? ''}', subtitle: repo, url: issue['html_url'], description: issue['body'] ?? '',
      meta: [DetailMeta(label: 'Author', value: issue['user']?['login'] ?? ''), DetailMeta(label: 'Updated', value: timeAgo(issue['updated_at']))]);
  }

  Future<void> _aiReview(BuildContext context, dynamic pr, TeamData td) async {
    final repoUrl = (pr['repository_url'] ?? '').toString();
    final parts = repoUrl.split('/');
    if (parts.length < 2 || td.github == null || td.claude == null) return;
    final owner = parts[parts.length - 2];
    final repo = parts.last;
    final number = pr['number'] as int;

    showDialog(context: context, builder: (_) => _AIReviewDialog(owner: owner, repo: repo, number: number, prTitle: pr['title'] ?? '', prBody: pr['body'] ?? '', td: td));
  }

  Future<void> _analyzePR(BuildContext context, dynamic pr, TeamData td) async {
    final repoUrl = (pr['repository_url'] ?? '').toString();
    final parts = repoUrl.split('/');
    if (parts.length < 2 || td.github == null) return;
    showDialog(context: context, builder: (_) => _PRAnalysisDialog(owner: parts[parts.length - 2], repo: parts.last, number: pr['number'] as int, github: td.github!));
  }
}

class _PRAnalysisDialog extends StatefulWidget {
  final String owner, repo;
  final int number;
  final dynamic github;
  const _PRAnalysisDialog({required this.owner, required this.repo, required this.number, required this.github});
  @override
  State<_PRAnalysisDialog> createState() => _PRAnalysisDialogState();
}

class _PRAnalysisDialogState extends State<_PRAnalysisDialog> {
  bool _loading = true; List<dynamic> _files = []; List<Map<String, String>> _suggestions = []; String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final files = await widget.github.getPRFiles(widget.owner, widget.repo, widget.number);
      final suggestions = widget.github.generateReviewSuggestions(files);
      if (mounted) setState(() { _files = files; _suggestions = suggestions; _loading = false; });
    } catch (e) { if (mounted) setState(() { _error = '$e'; _loading = false; }); }
  }

  @override
  Widget build(BuildContext context) {
    final totalAdd = _files.fold<int>(0, (s, f) => s + ((f['additions'] ?? 0) as int));
    final totalDel = _files.fold<int>(0, (s, f) => s + ((f['deletions'] ?? 0) as int));
    return Dialog(
      backgroundColor: AppColors.bg1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600), child: _loading
        ? const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
        : _error != null
          ? Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text('Error', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.red)), const SizedBox(height: 8), Text(_error!, style: const TextStyle(color: AppColors.text2)), const SizedBox(height: 16), OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))]))
          : SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${widget.owner}/${widget.repo} #${widget.number}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text0)),
              const SizedBox(height: 6),
              Text('+$totalAdd / -$totalDel \u00B7 ${_files.length} files', style: const TextStyle(fontSize: 12, color: AppColors.text2)),
              const SizedBox(height: 16),
              if (_suggestions.isNotEmpty) ...[const SectionTitle('Review Suggestions'), ..._suggestions.map((s) => Container(
                margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.bg0, borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s['msg'] ?? '', style: const TextStyle(fontSize: 13, color: AppColors.text1)), Text(s['file'] ?? '', style: const TextStyle(fontSize: 11, color: AppColors.text3, fontFamily: 'monospace'))]),
              ))]
              else Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.greenSoft, borderRadius: BorderRadius.circular(8)), child: const Text('Looks clean!', style: TextStyle(color: AppColors.green, fontSize: 13, fontWeight: FontWeight.w500))),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: () => launchUrl(Uri.parse('https://github.com/${widget.owner}/${widget.repo}/pull/${widget.number}'), mode: LaunchMode.externalApplication), child: const Text('Open on GitHub')),
              ]),
            ])),
      ),
    );
  }
}

// ── AI Review Dialog ──────────────────────────────────────────

class _AIReviewDialog extends StatefulWidget {
  final String owner, repo, prTitle, prBody;
  final int number;
  final TeamData td;
  const _AIReviewDialog({required this.owner, required this.repo, required this.number, required this.prTitle, required this.prBody, required this.td});
  @override
  State<_AIReviewDialog> createState() => _AIReviewDialogState();
}

class _AIReviewDialogState extends State<_AIReviewDialog> {
  bool _loading = true;
  String _status = 'Fetching PR files...';
  String _raw = '';
  String _output = '';
  final _scrollCtrl = ScrollController();
  List<dynamic> _comments = [];
  String? _error;
  bool _posting = false;

  @override
  void initState() { super.initState(); _review(); }
  @override
  void dispose() { _scrollCtrl.dispose(); super.dispose(); }

  void _addChunk(String chunk) {
    if (!mounted) return;
    setState(() => _output += chunk);
    Future.microtask(() {
      if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });
  }

  Future<void> _review() async {
    try {
      final files = await widget.td.github!.getPRFiles(widget.owner, widget.repo, widget.number);
      setState(() => _status = 'Claude is reviewing ${files.length} files...');

      setState(() => _status = 'Claude is reviewing...');
      final review = await widget.td.claude!.reviewPR(
        prTitle: widget.prTitle,
        prDescription: widget.prBody,
        files: files.cast<Map<String, dynamic>>(),
        onLog: _addChunk,
      );

      if (mounted) setState(() { _comments = review.comments.map((c) => {'file': c.file, 'comment': c.comment, 'severity': c.severity}).toList(); _raw = review.raw; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _postAsComment() async {
    if (_posting) return;
    setState(() => _posting = true);
    try {
      // Build review comment body
      final buf = StringBuffer();
      buf.writeln('## Code Review\n');
      for (final c in _comments) {
        final sev = c['severity'] ?? 'info';
        final icon = sev == 'critical' ? '\u{1F6A8}' : sev == 'warning' ? '\u26A0\uFE0F' : sev == 'suggestion' ? '\u{1F4A1}' : '\u2705';
        buf.writeln('$icon **${c['file']}**');
        buf.writeln('${c['comment']}\n');
      }

      // Post as a PR comment (using the user's GitHub token — appears as them)
      final url = 'https://api.github.com/repos/${widget.owner}/${widget.repo}/issues/${widget.number}/comments';
      final res = await _postGitHub(url, {'body': buf.toString()});

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res ? 'Review posted to PR #${widget.number}' : 'Failed to post'), backgroundColor: res ? AppColors.green : AppColors.red),
        );
      }
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _posting = false; });
    }
  }

  Future<bool> _postGitHub(String url, Map<String, dynamic> body) async {
    final res = await http.post(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer ${widget.td.config.github!.token}', 'Accept': 'application/vnd.github+json', 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return res.statusCode == 201;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.bg1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 650),
        child: _loading
            ? Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)),
                  const SizedBox(width: 10),
                  Text(_status, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text1)),
                ]),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity, height: 350,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFF1e1e2e), borderRadius: BorderRadius.circular(8)),
                  child: SingleChildScrollView(
                    controller: _scrollCtrl,
                    child: SelectableText(
                      _output.isEmpty ? '\u276F Waiting for Claude...' : _output,
                      style: TextStyle(fontSize: 12, color: _output.isEmpty ? const Color(0xFF585b70) : const Color(0xFFcdd6f4), fontFamily: 'monospace', height: 1.6),
                    ),
                  ),
                ),
              ]))
            : _error != null
                ? Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Error', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.red)),
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: AppColors.text2, fontSize: 12)),
                    const SizedBox(height: 16),
                    OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                  ]))
                : SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Text('\u{1F916}', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('AI Review', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text0))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: AppColors.accentSurface, borderRadius: BorderRadius.circular(6)),
                        child: const Text('Claude', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.accent)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text('${widget.owner}/${widget.repo} #${widget.number}', style: const TextStyle(fontSize: 12, color: AppColors.text3)),
                    const SizedBox(height: 16),

                    ..._comments.map((c) {
                      final sev = c['severity'] ?? 'info';
                      Color sevColor;
                      IconData sevIcon;
                      switch (sev) {
                        case 'critical': sevColor = AppColors.red; sevIcon = Icons.error;
                        case 'warning': sevColor = AppColors.yellow; sevIcon = Icons.warning;
                        case 'suggestion': sevColor = AppColors.blue; sevIcon = Icons.lightbulb;
                        default: sevColor = AppColors.green; sevIcon = Icons.check_circle;
                      }
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppColors.bg0, borderRadius: BorderRadius.circular(8), border: Border(left: BorderSide(color: sevColor, width: 3))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Icon(sevIcon, size: 14, color: sevColor),
                            const SizedBox(width: 6),
                            Text(c['file'] ?? '', style: TextStyle(fontSize: 11, color: sevColor, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
                          ]),
                          const SizedBox(height: 4),
                          Text(c['comment'] ?? '', style: const TextStyle(fontSize: 13, color: AppColors.text1, height: 1.5)),
                        ]),
                      );
                    }),

                    const SizedBox(height: 12),
                    const Text('CLI Output', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text0)),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFF1e1e2e), borderRadius: BorderRadius.circular(8)),
                      child: SelectableText(_raw, style: const TextStyle(fontSize: 12, color: Color(0xFFcdd6f4), fontFamily: 'monospace', height: 1.5)),
                    ),
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _posting ? null : _postAsComment,
                        icon: _posting ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send, size: 16),
                        label: const Text('Post as my comment'),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    const Text('Comment will be posted under your GitHub account', style: TextStyle(fontSize: 11, color: AppColors.text3)),
                  ])),
      ),
    );
  }
}

