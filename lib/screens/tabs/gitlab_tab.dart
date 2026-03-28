import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/app_state.dart';
import '../../services/claude_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

class GitLabTab extends StatelessWidget {
  const GitLabTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, _) {
      final td = state.currentTeam;
      if (td == null) return const SizedBox.shrink();
      return ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          StatCard(value: '${td.glMyMRs.length}', label: 'My MRs', color: AppColors.yellow, icon: Icons.merge_rounded),
          const SizedBox(width: 10),
          StatCard(value: '${td.glReviews.length}', label: 'Assigned MRs', color: AppColors.orange, icon: Icons.rate_review_rounded),
          const SizedBox(width: 10),
          StatCard(value: '${td.glAssigned.length}', label: 'Issues', color: AppColors.green, icon: Icons.task_alt_rounded),
        ]),
        const SizedBox(height: 24),
        if (td.glReviews.isNotEmpty) ...[const SectionTitle('Assigned Merge Requests'), ...td.glReviews.map((mr) => _GitLabMRCard(mr: mr, td: td))],
        if (td.glMyMRs.isNotEmpty) ...[const SectionTitle('My Merge Requests'), ...td.glMyMRs.map((mr) => _GitLabMRCard(mr: mr, td: td))],
        if (td.glAssigned.isNotEmpty) ...[const SectionTitle('Assigned Issues'), ...td.glAssigned.map((i) => _GitLabIssueCard(issue: i, td: td))],
        if (td.glReviews.isEmpty && td.glMyMRs.isEmpty && td.glAssigned.isEmpty) const EmptyState(icon: '\u{1F389}', message: 'Nothing here'),
      ]);
    });
  }
}

// ── MR Card ──────────────────────────────────────────────────

class _GitLabMRCard extends StatefulWidget {
  final dynamic mr;
  final TeamData td;
  const _GitLabMRCard({required this.mr, required this.td});
  @override
  State<_GitLabMRCard> createState() => _GitLabMRCardState();
}

class _GitLabMRCardState extends State<_GitLabMRCard> {
  dynamic get mr => widget.mr;
  TeamData get td => widget.td;

  @override
  Widget build(BuildContext context) {
    final hasClaude = td.claude != null;
    final src = mr['source_branch'] ?? '';
    final dst = mr['target_branch'] ?? '';
    final labels = (mr['labels'] ?? []) as List;
    final projectId = mr['project_id'];
    final iid = mr['iid'];
    final cacheKey = 'gl_mr_${projectId}_$iid';
    final hasCachedReview = td.aiCache.reviews.containsKey(cacheKey);

    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showMRDetail(context),
        child: Padding(padding: const EdgeInsets.all(14), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const ServiceIcon(label: '\u{1F98A}', bg: AppColors.yellowSoft, fg: AppColors.yellow),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('!$iid ${mr['title'] ?? ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text0), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  StatusPill(label: mr['state'] ?? '', category: mr['state'] == 'opened' ? 'progress' : mr['state'] == 'merged' ? 'done' : 'blocked'),
                  if (mr['draft'] == true) const StatusPill(label: 'Draft', category: 'todo'),
                  Text('$src \u2192 $dst', style: const TextStyle(fontSize: 12, color: AppColors.text2)),
                  Text(timeAgo(mr['updated_at']?.toString()), style: const TextStyle(fontSize: 12, color: AppColors.text3)),
                  ...labels.take(3).map((l) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.purpleSoft, borderRadius: BorderRadius.circular(8)),
                    child: Text(l is String ? l : '$l', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.purple)),
                  )),
                ]),
              ])),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.text3),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              OutlinedButton.icon(
                onPressed: () => _analyzeMR(context),
                icon: const Icon(Icons.search, size: 16), label: const Text('Analyze'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              if (hasClaude) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    await showDialog(context: context, builder: (_) => _GLAIReviewDialog(mr: mr, td: td));
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

  void _showMRDetail(BuildContext context) {
    final labels = (mr['labels'] ?? []) as List;
    final src = mr['source_branch'] ?? '';
    final dst = mr['target_branch'] ?? '';
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
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.yellow.withAlpha(15), AppColors.orange.withAlpha(8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.yellow.withAlpha(25)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFF97316)]),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('!${mr['iid']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                    const SizedBox(width: 10),
                    StatusPill(label: mr['state'] ?? '', category: mr['state'] == 'opened' ? 'progress' : mr['state'] == 'merged' ? 'done' : 'blocked'),
                    if (mr['draft'] == true) ...[const SizedBox(width: 8), const StatusPill(label: 'Draft', category: 'todo')],
                    const Spacer(),
                    const Text('Merge Request', style: TextStyle(fontSize: 12, color: AppColors.text2)),
                  ]),
                  const SizedBox(height: 16),
                  Text(mr['title'] ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text0, letterSpacing: -0.5, height: 1.2)),
                  const SizedBox(height: 8),
                  Text('$src \u2192 $dst', style: const TextStyle(fontSize: 13, color: AppColors.text2, fontFamily: 'monospace')),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(children: [
                  _metaCard('\u{1F464}', 'Author', mr['author']?['name'] ?? '-', AppColors.blue),
                  const SizedBox(width: 10),
                  _metaCard('\u{1F553}', 'Updated', timeAgo(mr['updated_at']?.toString()), AppColors.purple),
                  const SizedBox(width: 10),
                  _metaCard('\u{1F4AC}', 'Comments', '${mr['user_notes_count'] ?? 0}', AppColors.cyan),
                ]),
              ),
              if (labels.isNotEmpty) Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(spacing: 6, runSpacing: 6, children: labels.map((l) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.purpleSoft, borderRadius: BorderRadius.circular(10)),
                  child: Text(l is String ? l : '$l', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.purple)),
                )).toList()),
              ),
              if ((mr['description'] ?? '').toString().isNotEmpty) Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Container(
                  width: double.infinity, padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: AppColors.bg1, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.borderSubtle)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(width: 3, height: 16, decoration: BoxDecoration(color: AppColors.yellow, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 10),
                      const Text('Description', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text0)),
                    ]),
                    const SizedBox(height: 14),
                    SelectableText(mr['description'], style: const TextStyle(fontSize: 14, color: AppColors.text1, height: 1.8)),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 36),
                child: SizedBox(width: double.infinity, child: ElevatedButton.icon(
                  onPressed: () {
                    final url = mr['web_url'];
                    if (url != null) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 16), label: const Text('Open in GitLab'),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: AppColors.yellow),
                )),
              ),
            ])),
          ),
        ),
      ),
    );
  }

  void _analyzeMR(BuildContext context) {
    final description = mr['description'] ?? '';
    final title = mr['title'] ?? '';
    final suggestions = <Map<String, String>>[];
    if (title.length < 10) suggestions.add({'msg': 'MR title is very short — add more context', 'type': 'suggestion'});
    if (description.isEmpty) suggestions.add({'msg': 'No description — consider adding context for reviewers', 'type': 'warning'});
    if (description.contains('TODO') || description.contains('FIXME')) suggestions.add({'msg': 'Description contains TODO/FIXME', 'type': 'todo'});
    if (mr['draft'] == true) suggestions.add({'msg': 'MR is still in draft', 'type': 'info'});

    showDialog(context: context, builder: (_) => Dialog(
      backgroundColor: AppColors.bg1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
      child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('MR !${mr['iid']} Analysis', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text0)),
        const SizedBox(height: 12),
        if (suggestions.isEmpty)
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.greenSoft, borderRadius: BorderRadius.circular(8)),
            child: const Text('Looks good — no obvious issues.', style: TextStyle(color: AppColors.green, fontSize: 13)))
        else
          ...suggestions.map((s) => Container(
            margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.bg0, borderRadius: BorderRadius.circular(8)),
            child: Text(s['msg']!, style: const TextStyle(fontSize: 13, color: AppColors.text1)),
          )),
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerRight, child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))),
      ])),
    ));
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

class _GitLabIssueCard extends StatefulWidget {
  final dynamic issue;
  final TeamData td;
  const _GitLabIssueCard({required this.issue, required this.td});
  @override
  State<_GitLabIssueCard> createState() => _GitLabIssueCardState();
}

class _GitLabIssueCardState extends State<_GitLabIssueCard> {
  dynamic get issue => widget.issue;
  TeamData get td => widget.td;

  @override
  Widget build(BuildContext context) {
    final hasClaude = td.claude != null;
    final labels = (issue['labels'] ?? []) as List;
    final projectId = issue['project_id'];
    final iid = issue['iid'];
    final cacheKey = 'gl_issue_${projectId}_$iid';
    final hasCachedPlan = td.aiCache.plans.containsKey(cacheKey);
    final state = issue['state'] ?? '';
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
                Text('#$iid ${issue['title'] ?? ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text0), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  StatusPill(label: state, category: state == 'opened' ? 'progress' : 'done'),
                  Text(timeAgo(issue['updated_at']?.toString()), style: const TextStyle(fontSize: 12, color: AppColors.text3)),
                  ...labels.take(3).map((l) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.cyanSoft, borderRadius: BorderRadius.circular(8)),
                    child: Text(l is String ? l : '$l', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.cyan)),
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
      final s = (l is String ? l : '$l').toLowerCase();
      if (s.contains('bug')) return 'bug';
      if (s.contains('feature') || s.contains('enhancement')) return 'feature';
    }
    return 'issue';
  }

  void _showIssueDetail(BuildContext context) {
    final labels = (issue['labels'] ?? []) as List;
    final state = issue['state'] ?? '';
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
                      child: Text('#${issue['iid']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                    const SizedBox(width: 10),
                    StatusPill(label: state, category: state == 'opened' ? 'progress' : 'done'),
                    const Spacer(),
                    const Text('Issue', style: TextStyle(fontSize: 12, color: AppColors.text2)),
                  ]),
                  const SizedBox(height: 16),
                  Text(issue['title'] ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text0, letterSpacing: -0.5, height: 1.2)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(children: [
                  _metaCard('\u{1F464}', 'Author', issue['author']?['name'] ?? '-', AppColors.blue),
                  const SizedBox(width: 10),
                  _metaCard('\u{1F553}', 'Updated', timeAgo(issue['updated_at']?.toString()), AppColors.purple),
                  const SizedBox(width: 10),
                  _metaCard('\u{1F4AC}', 'Comments', '${issue['user_notes_count'] ?? 0}', AppColors.cyan),
                ]),
              ),
              if (labels.isNotEmpty) Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(spacing: 6, runSpacing: 6, children: labels.map((l) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.cyanSoft, borderRadius: BorderRadius.circular(10)),
                  child: Text(l is String ? l : '$l', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.cyan)),
                )).toList()),
              ),
              if ((issue['description'] ?? '').toString().isNotEmpty) Padding(
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
                    SelectableText(issue['description'], style: const TextStyle(fontSize: 14, color: AppColors.text1, height: 1.8)),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 36),
                child: SizedBox(width: double.infinity, child: ElevatedButton.icon(
                  onPressed: () {
                    final url = issue['web_url'];
                    if (url != null) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 16), label: const Text('Open in GitLab'),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: AppColors.green),
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
    final projectId = issue['project_id'];
    final iid = issue['iid'];
    final cacheKey = 'gl_issue_${projectId}_$iid';

    final cached = td.aiCache.plans[cacheKey];
    if (cached != null) {
      if (!context.mounted) return;
      await showDialog(context: context, builder: (_) => _GLAIPlanDialog(
        cacheKey: cacheKey, summary: issue['title'] ?? '', claude: td.claude!, cached: cached, td: td,
      ));
      if (mounted) setState(() {});
      return;
    }

    if (!context.mounted) return;
    await showDialog(context: context, builder: (_) => _GLAIPlanDialog(
      cacheKey: cacheKey,
      summary: issue['title'] ?? '',
      description: issue['description'] ?? '',
      type: _detectType((issue['labels'] ?? []) as List) == 'bug' ? 'Bug' : 'Task',
      claude: td.claude!,
      td: td,
    ));
    if (mounted) setState(() {});
  }

  Future<void> _howToTest(BuildContext context) async {
    if (td.claude == null) return;
    final projectId = issue['project_id'];
    final iid = issue['iid'];
    final cacheKey = 'gl_issue_${projectId}_$iid';
    final cached = td.aiCache.plans[cacheKey];
    final planContext = cached?.raw ?? '';

    await showDialog(context: context, builder: (_) => _GLAIPlanDialog(
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

// ── AI Plan Dialog (for GitLab issues) ───────────────────────

class _GLAIPlanDialog extends StatefulWidget {
  final String cacheKey, summary;
  final String? description, type;
  final ClaudeService claude;
  final ImplementationPlan? cached;
  final TeamData td;

  const _GLAIPlanDialog({required this.cacheKey, required this.summary, this.description, this.type, required this.claude, this.cached, required this.td});
  @override
  State<_GLAIPlanDialog> createState() => _GLAIPlanDialogState();
}

class _GLAIPlanDialogState extends State<_GLAIPlanDialog> {
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

// ── AI Review Dialog (for GitLab MRs) ────────────────────────

class _GLAIReviewDialog extends StatefulWidget {
  final dynamic mr;
  final TeamData td;
  const _GLAIReviewDialog({required this.mr, required this.td});
  @override
  State<_GLAIReviewDialog> createState() => _GLAIReviewDialogState();
}

class _GLAIReviewDialogState extends State<_GLAIReviewDialog> {
  bool _loading = true;
  String _status = 'Fetching MR changes...';
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
      final projectId = widget.mr['project_id'] as int;
      final iid = widget.mr['iid'] as int;
      final cacheKey = 'gl_mr_${projectId}_$iid';

      // Check cache
      final cached = widget.td.aiCache.reviews[cacheKey];
      if (cached != null) {
        if (mounted) setState(() {
          _comments = cached.comments.map((c) => {'file': c.file, 'comment': c.comment, 'severity': c.severity}).toList();
          _raw = cached.raw;
          _loading = false;
        });
        return;
      }

      // Fetch MR diff
      final diffText = await widget.td.gitlab!.getMRDiff(projectId, iid);

      // Parse diff into files
      final files = <Map<String, dynamic>>[];
      if (diffText.isNotEmpty) {
        final fileChunks = diffText.split(RegExp(r'^---', multiLine: true));
        for (final chunk in fileChunks) {
          if (chunk.trim().isEmpty) continue;
          final nameMatch = RegExp(r'^\+\+\+ (.+)$', multiLine: true).firstMatch(chunk);
          final filename = nameMatch?.group(1) ?? 'unknown';
          final additions = RegExp(r'^\+[^+]', multiLine: true).allMatches(chunk).length;
          final deletions = RegExp(r'^-[^-]', multiLine: true).allMatches(chunk).length;
          files.add({'filename': filename, 'additions': additions, 'deletions': deletions, 'patch': chunk.length > 4000 ? chunk.substring(0, 4000) : chunk});
        }
      }

      if (files.isEmpty && diffText.isNotEmpty) {
        files.add({'filename': 'MR diff', 'additions': 0, 'deletions': 0, 'patch': diffText.length > 6000 ? diffText.substring(0, 6000) : diffText});
      }

      setState(() => _status = 'Claude is reviewing ${files.length} files...');

      final review = await widget.td.claude!.reviewPR(
        prTitle: widget.mr['title'] ?? '',
        prDescription: widget.mr['description'] ?? '',
        files: files,
        onLog: _addChunk,
      );

      // Cache the review
      widget.td.aiCache.reviews[cacheKey] = review;

      if (mounted) setState(() {
        _comments = review.comments.map((c) => {'file': c.file, 'comment': c.comment, 'severity': c.severity}).toList();
        _raw = review.raw;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _postAsComment() async {
    if (_posting) return;
    setState(() => _posting = true);
    try {
      final buf = StringBuffer();
      buf.writeln('## Code Review\n');
      for (final c in _comments) {
        final sev = c['severity'] ?? 'info';
        final icon = sev == 'critical' ? '\u{1F6A8}' : sev == 'warning' ? '\u26A0\uFE0F' : sev == 'suggestion' ? '\u{1F4A1}' : '\u2705';
        buf.writeln('$icon **${c['file']}**');
        buf.writeln('${c['comment']}\n');
      }

      final projectId = widget.mr['project_id'] as int;
      final iid = widget.mr['iid'] as int;
      final ok = await widget.td.gitlab!.postMRNote(projectId, iid, buf.toString());

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? 'Review posted to MR !$iid' : 'Failed to post'), backgroundColor: ok ? AppColors.green : AppColors.red),
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
                    Text('!${widget.mr['iid']}', style: const TextStyle(fontSize: 12, color: AppColors.text3)),
                    const SizedBox(height: 16),

                    ..._comments.map((c) {
                      final sev = c['severity'] ?? 'info';
                      Color sevColor; IconData sevIcon;
                      switch (sev) {
                        case 'critical': sevColor = AppColors.red; sevIcon = Icons.error;
                        case 'warning': sevColor = AppColors.yellow; sevIcon = Icons.warning;
                        case 'suggestion': sevColor = AppColors.blue; sevIcon = Icons.lightbulb;
                        default: sevColor = AppColors.green; sevIcon = Icons.check_circle;
                      }
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
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
                      width: double.infinity, padding: const EdgeInsets.all(12),
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
                    const Text('Comment will be posted under your GitLab account', style: TextStyle(fontSize: 11, color: AppColors.text3)),
                  ])),
      ),
    );
  }
}
