import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/app_state.dart';
import '../../services/claude_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

class GitHubTab extends StatelessWidget {
  const GitHubTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, _) {
      final td = state.currentTeam;
      if (td == null) return const SizedBox.shrink();
      return ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          StatCard(value: '${td.ghMyPRs.length}', label: 'My PRs', color: AppColors.accent, icon: Icons.merge_rounded),
          const SizedBox(width: 10),
          StatCard(value: '${td.ghReviewReqs.length}', label: 'Reviews', color: AppColors.orange, icon: Icons.rate_review_rounded),
          const SizedBox(width: 10),
          StatCard(value: '${td.ghAssigned.length}', label: 'Issues', color: AppColors.green, icon: Icons.task_alt_rounded),
        ]),
        const SizedBox(height: 24),
        if (td.ghReviewReqs.isNotEmpty) ...[const SectionTitle('Review Requests'), ...td.ghReviewReqs.map((pr) => _GitHubPRCard(pr: pr, td: td))],
        if (td.ghMyPRs.isNotEmpty) ...[const SectionTitle('My Pull Requests'), ...td.ghMyPRs.map((pr) => _GitHubPRCard(pr: pr, td: td))],
        if (td.ghAssigned.isNotEmpty) ...[const SectionTitle('Assigned Issues'), ...td.ghAssigned.map((i) => _GitHubIssueCard(issue: i, td: td))],
        if (td.ghReviewReqs.isEmpty && td.ghMyPRs.isEmpty && td.ghAssigned.isEmpty) const EmptyState(icon: '\u{1F389}', message: 'Nothing on your plate'),
      ]);
    });
  }
}

// ── PR Card ──────────────────────────────────────────────────

class _GitHubPRCard extends StatefulWidget {
  final dynamic pr;
  final TeamData td;
  const _GitHubPRCard({required this.pr, required this.td});
  @override
  State<_GitHubPRCard> createState() => _GitHubPRCardState();
}

class _GitHubPRCardState extends State<_GitHubPRCard> {
  dynamic get pr => widget.pr;
  TeamData get td => widget.td;

  String get _repo => (pr['repository_url'] ?? '').toString().split('/').reversed.take(2).toList().reversed.join('/');
  String get _owner => _repo.split('/').first;
  String get _repoName => _repo.split('/').last;
  int get _number => pr['number'] as int;

  @override
  Widget build(BuildContext context) {
    final hasClaude = td.claude != null;
    final labels = (pr['labels'] ?? []) as List;
    final cacheKey = 'gh_pr_${_owner}_${_repoName}_$_number';
    final hasCachedReview = td.aiCache.reviews.containsKey(cacheKey);

    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showPRDetail(context),
        child: Padding(padding: const EdgeInsets.all(14), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const ServiceIcon(label: '\u{2693}', bg: AppColors.accentSurface, fg: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('#$_number ${pr['title'] ?? ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text0), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  StatusPill(label: pr['state'] ?? '', category: pr['state'] == 'open' ? 'progress' : 'done'),
                  if (pr['draft'] == true) const StatusPill(label: 'Draft', category: 'todo'),
                  Text(_repo, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
                  Text(timeAgo(pr['updated_at']), style: const TextStyle(fontSize: 12, color: AppColors.text3)),
                  ...labels.take(3).map((l) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.purpleSoft, borderRadius: BorderRadius.circular(8)),
                    child: Text(l['name'] ?? '', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.purple)),
                  )),
                ]),
              ])),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.text3),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              OutlinedButton.icon(
                onPressed: () => _analyzePR(context),
                icon: const Icon(Icons.search, size: 16), label: const Text('Analyze PR'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              if (hasClaude) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    await showDialog(context: context, builder: (_) => _GHAIReviewDialog(owner: _owner, repo: _repoName, number: _number, prTitle: pr['title'] ?? '', prBody: pr['body'] ?? '', td: td));
                    if (mounted) setState(() {});
                  },
                  icon: Icon(hasCachedReview ? Icons.play_arrow_rounded : Icons.smart_toy, size: 16),
                  label: Text(hasCachedReview ? 'Continue review' : 'AI Review'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    backgroundColor: hasCachedReview ? AppColors.green : AppColors.accent,
                  ),
                ),
              ],
            ]),
          ],
        )),
      ),
    ));
  }

  void _showPRDetail(BuildContext context) {
    final labels = (pr['labels'] ?? []) as List;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppColors.bg0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Hero header
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.accent.withAlpha(15), AppColors.purple.withAlpha(8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.accent.withAlpha(25)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('#$_number', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                    const SizedBox(width: 10),
                    StatusPill(label: pr['state'] ?? '', category: pr['state'] == 'open' ? 'progress' : 'done'),
                    if (pr['draft'] == true) ...[const SizedBox(width: 8), const StatusPill(label: 'Draft', category: 'todo')],
                    const Spacer(),
                    const Text('Pull Request', style: TextStyle(fontSize: 12, color: AppColors.text2)),
                  ]),
                  const SizedBox(height: 16),
                  Text(pr['title'] ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text0, letterSpacing: -0.5, height: 1.2)),
                  const SizedBox(height: 8),
                  Text(_repo, style: const TextStyle(fontSize: 13, color: AppColors.text2, fontFamily: 'monospace')),
                ]),
              ),

              // Meta cards
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(children: [
                  _metaCard('\u{1F464}', 'Author', pr['user']?['login'] ?? '-', AppColors.blue),
                  const SizedBox(width: 10),
                  _metaCard('\u{1F553}', 'Updated', timeAgo(pr['updated_at']), AppColors.purple),
                  const SizedBox(width: 10),
                  _metaCard('\u{1F4AC}', 'Comments', '${pr['comments'] ?? 0}', AppColors.cyan),
                ]),
              ),

              // Labels
              if (labels.isNotEmpty) Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(spacing: 6, runSpacing: 6, children: labels.map((l) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.purpleSoft, borderRadius: BorderRadius.circular(10)),
                  child: Text(l['name'] ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.purple)),
                )).toList()),
              ),

              // Description
              if ((pr['body'] ?? '').toString().isNotEmpty) Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Container(
                  width: double.infinity, padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: AppColors.bg1, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.borderSubtle)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(width: 3, height: 16, decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 10),
                      const Text('Description', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text0)),
                    ]),
                    const SizedBox(height: 14),
                    SelectableText(pr['body'], style: const TextStyle(fontSize: 14, color: AppColors.text1, height: 1.8)),
                  ]),
                ),
              ),

              // Open in GitHub
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 36),
                child: SizedBox(width: double.infinity, child: ElevatedButton.icon(
                  onPressed: () {
                    final url = pr['html_url'];
                    if (url != null) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 16), label: const Text('Open in GitHub'),
                )),
              ),
            ])),
          ),
        ),
      ),
    );
  }

  Future<void> _analyzePR(BuildContext context) async {
    if (td.github == null) return;
    showDialog(context: context, builder: (_) => _PRAnalysisDialog(owner: _owner, repo: _repoName, number: _number, github: td.github!));
  }

  Widget _metaCard(String emoji, String label, String value, Color c) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: c.withAlpha(10), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withAlpha(25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c), maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.text3)),
      ]),
    ));
  }
}

// ── Issue Card ───────────────────────────────────────────────

class _GitHubIssueCard extends StatefulWidget {
  final dynamic issue;
  final TeamData td;
  const _GitHubIssueCard({required this.issue, required this.td});
  @override
  State<_GitHubIssueCard> createState() => _GitHubIssueCardState();
}

class _GitHubIssueCardState extends State<_GitHubIssueCard> {
  dynamic get issue => widget.issue;
  TeamData get td => widget.td;

  String get _repo => (issue['repository_url'] ?? '').toString().split('/').reversed.take(2).toList().reversed.join('/');

  @override
  Widget build(BuildContext context) {
    final hasClaude = td.claude != null;
    final labels = (issue['labels'] ?? []) as List;
    final cacheKey = 'gh_issue_${issue['number']}';
    final hasCachedPlan = td.aiCache.plans.containsKey(cacheKey);
    final typeName = _detectType(labels);

    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showIssueDetail(context),
        child: Padding(padding: const EdgeInsets.all(14), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ServiceIcon(label: typeName == 'bug' ? '\u{1F41B}' : typeName == 'feature' ? '\u{1F680}' : '!', bg: AppColors.greenSoft, fg: AppColors.green),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('#${issue['number']} ${issue['title'] ?? ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text0), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  StatusPill(label: issue['state'] ?? '', category: issue['state'] == 'open' ? 'progress' : 'done'),
                  Text(_repo, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
                  Text(timeAgo(issue['updated_at']), style: const TextStyle(fontSize: 12, color: AppColors.text3)),
                  ...labels.take(3).map((l) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.cyanSoft, borderRadius: BorderRadius.circular(8)),
                    child: Text(l['name'] ?? '', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.cyan)),
                  )),
                ]),
              ])),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.text3),
            ]),
            if (hasClaude) ...[
              const SizedBox(height: 10),
              Row(children: [
                ElevatedButton.icon(
                  onPressed: () => _aiPlan(context),
                  icon: Icon(hasCachedPlan ? Icons.play_arrow_rounded : Icons.smart_toy, size: 16),
                  label: Text(hasCachedPlan ? 'Continue planning' : 'Plan with AI'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    backgroundColor: hasCachedPlan ? AppColors.green : AppColors.accent,
                  ),
                ),
                if (hasCachedPlan) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _howToTest(context),
                    icon: const Icon(Icons.science_rounded, size: 16),
                    label: const Text('How to test'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      foregroundColor: AppColors.purple,
                      side: const BorderSide(color: AppColors.purple),
                    ),
                  ),
                ],
              ]),
            ],
          ],
        )),
      ),
    ));
  }

  String _detectType(List labels) {
    for (final l in labels) {
      final s = ((l is Map ? l['name'] : l) ?? '').toString().toLowerCase();
      if (s.contains('bug')) return 'bug';
      if (s.contains('feature') || s.contains('enhancement')) return 'feature';
    }
    return 'issue';
  }

  void _showIssueDetail(BuildContext context) {
    final labels = (issue['labels'] ?? []) as List;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppColors.bg0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Hero header
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.green.withAlpha(15), AppColors.cyan.withAlpha(8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.green.withAlpha(25)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF06B6D4)]),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('#${issue['number']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                    const SizedBox(width: 10),
                    StatusPill(label: issue['state'] ?? '', category: issue['state'] == 'open' ? 'progress' : 'done'),
                    const Spacer(),
                    const Text('Issue', style: TextStyle(fontSize: 12, color: AppColors.text2)),
                  ]),
                  const SizedBox(height: 16),
                  Text(issue['title'] ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text0, letterSpacing: -0.5, height: 1.2)),
                  const SizedBox(height: 8),
                  Text(_repo, style: const TextStyle(fontSize: 13, color: AppColors.text2, fontFamily: 'monospace')),
                ]),
              ),

              // Meta cards
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(children: [
                  _metaCard('\u{1F464}', 'Author', issue['user']?['login'] ?? '-', AppColors.blue),
                  const SizedBox(width: 10),
                  _metaCard('\u{1F553}', 'Updated', timeAgo(issue['updated_at']), AppColors.purple),
                  const SizedBox(width: 10),
                  _metaCard('\u{1F4AC}', 'Comments', '${issue['comments'] ?? 0}', AppColors.cyan),
                ]),
              ),

              // Labels
              if (labels.isNotEmpty) Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(spacing: 6, runSpacing: 6, children: labels.map((l) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.cyanSoft, borderRadius: BorderRadius.circular(10)),
                  child: Text(l['name'] ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.cyan)),
                )).toList()),
              ),

              // Description
              if ((issue['body'] ?? '').toString().isNotEmpty) Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Container(
                  width: double.infinity, padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: AppColors.bg1, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.borderSubtle)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(width: 3, height: 16, decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 10),
                      const Text('Description', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text0)),
                    ]),
                    const SizedBox(height: 14),
                    SelectableText(issue['body'], style: const TextStyle(fontSize: 14, color: AppColors.text1, height: 1.8)),
                  ]),
                ),
              ),

              // Open in GitHub
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 36),
                child: SizedBox(width: double.infinity, child: ElevatedButton.icon(
                  onPressed: () {
                    final url = issue['html_url'];
                    if (url != null) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 16), label: const Text('Open in GitHub'),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                )),
              ),
            ])),
          ),
        ),
      ),
    );
  }

  Future<void> _aiPlan(BuildContext context) async {
    if (td.claude == null) return;
    final cacheKey = 'gh_issue_${issue['number']}';

    final cached = td.aiCache.plans[cacheKey];
    if (cached != null) {
      if (!context.mounted) return;
      await showDialog(context: context, builder: (_) => _GHAIPlanDialog(
        cacheKey: cacheKey, summary: issue['title'] ?? '', claude: td.claude!, cached: cached, td: td,
      ));
      if (mounted) setState(() {});
      return;
    }

    if (!context.mounted) return;
    await showDialog(context: context, builder: (_) => _GHAIPlanDialog(
      cacheKey: cacheKey,
      summary: issue['title'] ?? '',
      description: issue['body'] ?? '',
      type: _detectType((issue['labels'] ?? []) as List) == 'bug' ? 'Bug' : 'Task',
      claude: td.claude!,
      td: td,
    ));
    if (mounted) setState(() {});
  }

  Future<void> _howToTest(BuildContext context) async {
    if (td.claude == null) return;
    final cacheKey = 'gh_issue_${issue['number']}';
    final cached = td.aiCache.plans[cacheKey];
    final planContext = cached?.raw ?? '';

    await showDialog(context: context, builder: (_) => _GHAIPlanDialog(
      cacheKey: cacheKey,
      summary: 'How to test: ${issue['title'] ?? ''}',
      description: 'Based on the implementation plan below, tell me exactly how to test this. Include:\n- Manual testing steps\n- What to verify visually\n- Edge cases to check\n- Any API/state scenarios to validate\n\nPrevious implementation plan:\n$planContext',
      type: 'Test Plan',
      claude: td.claude!,
      td: td,
    ));
    if (mounted) setState(() {});
  }

  Widget _metaCard(String emoji, String label, String value, Color c) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: c.withAlpha(10), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withAlpha(25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c), maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.text3)),
      ]),
    ));
  }
}

// ── PR Analysis Dialog ───────────────────────────────────────

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
          ? Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Error', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.red)), const SizedBox(height: 8), Text(_error!, style: const TextStyle(color: AppColors.text2)), const SizedBox(height: 16), OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))]))
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

// ── AI Plan Dialog (for GitHub issues) ───────────────────────

class _GHAIPlanDialog extends StatefulWidget {
  final String cacheKey, summary;
  final String? description, type;
  final ClaudeService claude;
  final ImplementationPlan? cached;
  final TeamData td;

  const _GHAIPlanDialog({required this.cacheKey, required this.summary, this.description, this.type, required this.claude, this.cached, required this.td});
  @override
  State<_GHAIPlanDialog> createState() => _GHAIPlanDialogState();
}

class _GHAIPlanDialogState extends State<_GHAIPlanDialog> {
  final _scrollCtrl = ScrollController();
  final _promptCtrl = TextEditingController();
  final _promptFocus = FocusNode();
  bool _busy = false;
  String _output = '';

  @override
  void initState() {
    super.initState();
    if (widget.cached != null) {
      _output = widget.cached!.raw;
    } else {
      _runInitial();
    }
  }

  @override
  void dispose() { _scrollCtrl.dispose(); _promptCtrl.dispose(); _promptFocus.dispose(); super.dispose(); }

  void _appendOutput(String chunk) {
    if (!mounted) return;
    setState(() => _output += chunk);
    Future.microtask(() {
      if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });
  }

  Future<void> _runInitial() async {
    setState(() { _busy = true; _output = ''; });
    try {
      final plan = await widget.claude.planTicket(
        key: widget.cacheKey, summary: widget.summary,
        description: widget.description ?? '', type: widget.type ?? 'Task',
        onLog: _appendOutput,
      );
      widget.td.aiCache.plans[widget.cacheKey] = plan;
    } catch (e) {
      _appendOutput('\n\nError: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _sendFollowUp() async {
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty || _busy) return;
    _promptCtrl.clear();
    setState(() { _busy = true; _output += '\n\n\u2500\u2500\u2500 You \u2500\u2500\u2500\n$prompt\n\n'; });
    try {
      await widget.claude.sendPrompt(prompt: prompt, context: _output, onLog: _appendOutput);
    } catch (e) {
      _appendOutput('\n\nError: $e');
    }
    if (mounted) { setState(() => _busy = false); _promptFocus.requestFocus(); }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1a1b26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 600),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            decoration: const BoxDecoration(color: Color(0xFF24283b), borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
            child: Row(children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.accent, Color(0xFF5856D6)]), borderRadius: BorderRadius.circular(8)),
                alignment: Alignment.center,
                child: const Text('C', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.cacheKey, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFc0caf5))),
                Text(widget.summary, style: const TextStyle(fontSize: 11, color: Color(0xFF565f89)), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              if (_busy)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7aa2f7)))
              else if (widget.cached != null)
                IconButton(icon: const Icon(Icons.refresh_rounded, size: 18, color: Color(0xFF565f89)), onPressed: _runInitial, tooltip: 'Re-run'),
              IconButton(icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF565f89)), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Expanded(child: Container(
            width: double.infinity, color: const Color(0xFF1a1b26),
            child: SingleChildScrollView(
              controller: _scrollCtrl, padding: const EdgeInsets.all(16),
              child: SelectableText(
                _output.isEmpty ? (_busy ? 'Starting...' : 'Ready.') : _output,
                style: TextStyle(fontSize: 13, color: _output.isEmpty ? const Color(0xFF565f89) : const Color(0xFFa9b1d6), fontFamily: 'monospace', height: 1.7),
              ),
            ),
          )),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
            decoration: const BoxDecoration(color: Color(0xFF24283b), borderRadius: BorderRadius.vertical(bottom: Radius.circular(16))),
            child: Row(children: [
              const Text('\u276F ', style: TextStyle(fontSize: 14, color: Color(0xFF7aa2f7), fontFamily: 'monospace', fontWeight: FontWeight.w700)),
              Expanded(child: TextField(
                controller: _promptCtrl, focusNode: _promptFocus, enabled: !_busy,
                onSubmitted: (_) => _sendFollowUp(),
                style: const TextStyle(fontSize: 13, color: Color(0xFFc0caf5), fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  hintText: 'Ask a follow-up...', hintStyle: TextStyle(color: Color(0xFF444b6a)),
                  border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                  filled: false, contentPadding: EdgeInsets.zero, isDense: true,
                ),
              )),
              IconButton(
                onPressed: _busy ? null : _sendFollowUp,
                icon: Icon(Icons.send_rounded, size: 18, color: _busy ? const Color(0xFF444b6a) : const Color(0xFF7aa2f7)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── AI Review Dialog (for GitHub PRs) ────────────────────────

class _GHAIReviewDialog extends StatefulWidget {
  final String owner, repo, prTitle, prBody;
  final int number;
  final TeamData td;
  const _GHAIReviewDialog({required this.owner, required this.repo, required this.number, required this.prTitle, required this.prBody, required this.td});
  @override
  State<_GHAIReviewDialog> createState() => _GHAIReviewDialogState();
}

class _GHAIReviewDialogState extends State<_GHAIReviewDialog> {
  bool _loading = true;
  String _status = 'Fetching PR files...';
  String _raw = '';
  String _output = '';
  final _scrollCtrl = ScrollController();
  List<dynamic> _comments = [];
  final Set<int> _selected = {};
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
      final cacheKey = 'gh_pr_${widget.owner}_${widget.repo}_${widget.number}';

      // Check cache
      final cached = widget.td.aiCache.reviews[cacheKey];
      if (cached != null) {
        if (mounted) setState(() {
          _comments = cached.comments.map((c) => {'file': c.file, 'line': c.line, 'comment': c.comment, 'severity': c.severity}).toList();
          _selected.addAll(List.generate(_comments.length, (i) => i));
          _raw = cached.raw;
          _loading = false;
        });
        return;
      }

      final files = await widget.td.github!.getPRFiles(widget.owner, widget.repo, widget.number);
      setState(() => _status = 'Claude is reviewing ${files.length} files...');

      final review = await widget.td.claude!.reviewPR(
        prTitle: widget.prTitle,
        prDescription: widget.prBody,
        files: files.cast<Map<String, dynamic>>(),
        onLog: _addChunk,
      );

      // Cache the review
      widget.td.aiCache.reviews[cacheKey] = review;

      if (mounted) setState(() {
        _comments = review.comments.map((c) => {'file': c.file, 'line': c.line, 'comment': c.comment, 'severity': c.severity}).toList();
        _selected.addAll(List.generate(_comments.length, (i) => i));
        _raw = review.raw; _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _postAsComment() async {
    if (_posting || _selected.isEmpty) return;
    setState(() => _posting = true);
    try {
      final headers = {'Authorization': 'Bearer ${widget.td.config.github!.token}', 'Accept': 'application/vnd.github+json', 'Content-Type': 'application/json'};

      // Separate inline comments (have file+line) from general comments
      final inlineComments = <Map<String, dynamic>>[];
      final generalComments = <Map<String, dynamic>>[];
      for (int i = 0; i < _comments.length; i++) {
        if (!_selected.contains(i)) continue;
        final c = _comments[i];
        final line = (c['line'] as num?)?.toInt() ?? 0;
        if (c['file'] != 'general' && line > 0) {
          inlineComments.add(c);
        } else {
          generalComments.add(c);
        }
      }

      bool ok = true;

      // Post inline comments as a pull request review
      if (inlineComments.isNotEmpty) {
        final reviewComments = inlineComments.map((c) {
          return {'path': c['file'], 'line': c['line'], 'body': c['comment']};
        }).toList();

        final url = 'https://api.github.com/repos/${widget.owner}/${widget.repo}/pulls/${widget.number}/reviews';
        final res = await http.post(Uri.parse(url), headers: headers, body: jsonEncode({'event': 'COMMENT', 'comments': reviewComments}));
        if (res.statusCode != 200) ok = false;
      }

      // Post general comments as a regular PR comment
      if (generalComments.isNotEmpty) {
        final buf = StringBuffer();
        for (final c in generalComments) {
          buf.writeln('${c['comment']}\n');
        }
        final url = 'https://api.github.com/repos/${widget.owner}/${widget.repo}/issues/${widget.number}/comments';
        final res = await http.post(Uri.parse(url), headers: headers, body: jsonEncode({'body': buf.toString()}));
        if (res.statusCode != 201) ok = false;
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? 'Review posted to PR #${widget.number}' : 'Failed to post'), backgroundColor: ok ? AppColors.green : AppColors.red),
        );
      }
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _posting = false; });
    }
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
                    const SizedBox(height: 12),
                    // Select all / none
                    Row(children: [
                      Text('${_selected.length}/${_comments.length} selected', style: const TextStyle(fontSize: 12, color: AppColors.text2)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(() { _selected.addAll(List.generate(_comments.length, (i) => i)); }),
                        child: const Text('Select all', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent)),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => setState(() => _selected.clear()),
                        child: const Text('None', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text3)),
                      ),
                    ]),
                    const SizedBox(height: 12),

                    ...List.generate(_comments.length, (i) {
                      final c = _comments[i];
                      final sev = c['severity'] ?? 'info';
                      final isSelected = _selected.contains(i);
                      Color sevColor; IconData sevIcon;
                      switch (sev) {
                        case 'critical': sevColor = AppColors.red; sevIcon = Icons.error;
                        case 'warning': sevColor = AppColors.yellow; sevIcon = Icons.warning;
                        case 'suggestion': sevColor = AppColors.blue; sevIcon = Icons.lightbulb;
                        default: sevColor = AppColors.green; sevIcon = Icons.check_circle;
                      }
                      return GestureDetector(
                        onTap: () => setState(() { isSelected ? _selected.remove(i) : _selected.add(i); }),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.bg0 : AppColors.bg0.withAlpha(120),
                            borderRadius: BorderRadius.circular(8),
                            border: Border(left: BorderSide(color: isSelected ? sevColor : AppColors.bg3, width: 3)),
                          ),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2, right: 10),
                              child: Icon(isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: 20, color: isSelected ? AppColors.accent : AppColors.text3),
                            ),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Icon(sevIcon, size: 14, color: isSelected ? sevColor : AppColors.text3),
                                const SizedBox(width: 6),
                                Flexible(child: Text(c['file'] ?? '', style: TextStyle(fontSize: 11, color: isSelected ? sevColor : AppColors.text3, fontWeight: FontWeight.w600, fontFamily: 'monospace'))),
                                if ((c['line'] as num?)?.toInt() != null && (c['line'] as num).toInt() > 0) ...[
                                  const SizedBox(width: 6),
                                  Text('L${c['line']}', style: TextStyle(fontSize: 10, color: isSelected ? AppColors.accent : AppColors.text3, fontFamily: 'monospace')),
                                ],
                              ]),
                              const SizedBox(height: 4),
                              Text(c['comment'] ?? '', style: TextStyle(fontSize: 13, color: isSelected ? AppColors.text1 : AppColors.text3, height: 1.5)),
                            ])),
                          ]),
                        ),
                      );
                    }),

                    const SizedBox(height: 12),
                    const Text('CLI Output', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text0)),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity, padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFF1e1e2e), borderRadius: BorderRadius.circular(8)),
                      child: SelectableText(_raw, style: const TextStyle(fontSize: 12, color: Color(0xFFcdd6f4), fontFamily: 'monospace', height: 1.5)),
                    ),
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _posting || _selected.isEmpty ? null : _postAsComment,
                        icon: _posting ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send, size: 16),
                        label: Text('Post ${_selected.length} comment${_selected.length == 1 ? '' : 's'}'),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    const Text('Comment will be posted under your GitHub account', style: TextStyle(fontSize: 11, color: AppColors.text3)),
                  ])),
      ),
    );
  }
}
