import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/app_state.dart';
import '../../services/claude_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

class JiraTab extends StatelessWidget {
  const JiraTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, _) {
      final td = state.currentTeam;
      if (td == null) return const SizedBox.shrink();
      return ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          const Text('MY ISSUES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.text3, letterSpacing: 1.5)),
          const Spacer(),
          if (td.jiraBoards.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: AppColors.bg2, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8)),
              child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                value: state.selectedBoardKey,
                hint: const Text('Select board...', style: TextStyle(fontSize: 13, color: AppColors.text3)),
                dropdownColor: AppColors.bg1, style: const TextStyle(fontSize: 13, color: AppColors.text1),
                icon: const Icon(Icons.expand_more, size: 18, color: AppColors.text3),
                items: td.jiraBoards.map<DropdownMenuItem<String>>((b) {
                  final key = '0:${b['id']}';
                  return DropdownMenuItem(value: key, child: Text(b['name'] ?? '', overflow: TextOverflow.ellipsis));
                }).toList(),
                onChanged: (v) { if (v != null) state.selectBoard(v); },
              )),
            ),
        ]),
        const SizedBox(height: 16),
        if (td.jiraIssues.isEmpty) const EmptyState(icon: '\u2705', message: 'No issues assigned to you')
        else ...td.jiraIssues.map((issue) => _JiraCard(issue: issue, td: td)),
      ]);
    });
  }
}

class _JiraCard extends StatefulWidget {
  final dynamic issue;
  final TeamData td;
  const _JiraCard({required this.issue, required this.td});
  @override
  State<_JiraCard> createState() => _JiraCardState();
}

class _JiraCardState extends State<_JiraCard> {
  dynamic get issue => widget.issue;
  TeamData get td => widget.td;

  @override
  Widget build(BuildContext context) {
    final f = issue['fields'] ?? {};
    final statusCat = f['status']?['statusCategory']?['key'] ?? '';
    final statusName = f['status']?['name'] ?? '';
    final priority = f['priority']?['name'] ?? '';
    final typeName = (f['issuetype']?['name'] ?? '').toString().toLowerCase();
    final emoji = typeName.contains('bug') ? '\u{1F41B}' : typeName.contains('story') ? '\u{1F4D6}' : typeName.contains('epic') ? '\u26A1' : '\u2022';
    final key = issue['key'] ?? '';
    final hasClaude = td.claude != null;
    final hasCachedPlan = td.aiCache.plans.containsKey(key);

    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetail(context, key, f),
        child: Padding(padding: const EdgeInsets.all(14), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ServiceIcon(label: emoji, bg: AppColors.blueSoft, fg: AppColors.blue),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$key: ${f['summary'] ?? ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text0), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  StatusPill(label: statusName, category: statusCat),
                  if (priority.isNotEmpty) PriorityDot(priority: priority),
                  Text(f['project']?['name'] ?? '', style: const TextStyle(fontSize: 12, color: AppColors.text2)),
                ]),
              ])),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.text3),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              // Status change button
              OutlinedButton.icon(
                onPressed: () => _changeStatus(context, key),
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: const Text('Move'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              if (hasClaude) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _aiPlan(context, key, f),
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
                    onPressed: () => _howToTest(context, key, f),
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
              ],
            ]),
          ],
        )),
      ),
    ));
  }

  Future<void> _changeStatus(BuildContext context, String key) async {
    if (td.jira == null) return;
    try {
      final transitions = await td.jira!.getTransitions(key);
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: AppColors.bg1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: AppColors.accentSurface, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.swap_horiz_rounded, size: 20, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Move $key', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text0)),
                const Text('Choose new status', style: TextStyle(fontSize: 12, color: AppColors.text3)),
              ]),
            ]),
            const SizedBox(height: 20),
            ...transitions.map<Widget>((t) {
              final name = t['name'] ?? '';
              final id = t['id'] ?? '';
              final cat = t['to']?['statusCategory']?['key'] ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(width: double.infinity, child: OutlinedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    try {
                      await td.jira!.transitionIssue(key, id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$key moved to $name'), backgroundColor: AppColors.green));
                        context.read<AppState>().loadCurrentTeam();
                      }
                    } catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.red));
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: cat == 'done' ? AppColors.green : cat == 'indeterminate' ? AppColors.blue : AppColors.border),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    StatusPill(label: name, category: cat),
                  ]),
                )),
              );
            }),
            const SizedBox(height: 8),
          ]),
        ),
      ),
      ),
      );
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load transitions: $e'), backgroundColor: AppColors.red));
    }
  }

  Future<void> _showDetail(BuildContext context, String key, Map<String, dynamic> f) async {
    if (td.jira == null) return;
    String desc = '', reporter = '', created = '', assignee = '';
    List<dynamic> attachments = [];
    try {
      final full = await td.jira!.getIssue(key);
      final ff = full['fields'] ?? {};
      final rawDesc = ff['description'];
      desc = rawDesc is Map ? _adf(rawDesc) : (rawDesc is String ? rawDesc : '');
      reporter = ff['reporter']?['displayName'] ?? '';
      assignee = ff['assignee']?['displayName'] ?? '';
      created = ff['created'] ?? '';
      attachments = ff['attachment'] ?? [];
    } catch (_) {}
    if (!context.mounted) return;

    final statusCat = f['status']?['statusCategory']?['key'] ?? '';
    final statusName = f['status']?['name'] ?? '';
    final priorityName = f['priority']?['name'] ?? '';
    final typeName = f['issuetype']?['name'] ?? '';
    final projectName = f['project']?['name'] ?? '';
    final typeEmoji = typeName.toLowerCase().contains('bug') ? '\u{1F41B}' : typeName.toLowerCase().contains('story') ? '\u{1F4D6}' : typeName.toLowerCase().contains('epic') ? '\u26A1' : '\u{1F4CB}';

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppColors.bg0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 700),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Hero header card
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.accent.withAlpha(15), AppColors.purple.withAlpha(8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.accent.withAlpha(25)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Top badges row
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                    const SizedBox(width: 10),
                    StatusPill(label: statusName, category: statusCat),
                    const Spacer(),
                    Text('$typeEmoji $typeName', style: const TextStyle(fontSize: 12, color: AppColors.text2)),
                  ]),
                  const SizedBox(height: 16),
                  // Title
                  Text(f['summary'] ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.text0, letterSpacing: -0.7, height: 1.2)),
                  const SizedBox(height: 8),
                  Text(projectName, style: const TextStyle(fontSize: 13, color: AppColors.text2)),
                ]),
              ),

              // Meta cards row
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(children: [
                  _metaCard('\u{1F525}', 'Priority', priorityName.isNotEmpty ? priorityName : '-', AppColors.orange),
                  const SizedBox(width: 10),
                  _metaCard('\u{1F464}', 'Reporter', reporter.isNotEmpty ? reporter.split(' ').first : '-', AppColors.blue),
                  const SizedBox(width: 10),
                  _metaCard('\u{1F553}', 'Updated', timeAgo(f['updated']), AppColors.purple),
                  if (created.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    _metaCard('\u{1F4C5}', 'Created', timeAgo(created), AppColors.cyan),
                  ],
                ]),
              ),

              // Assignee
              if (assignee.isNotEmpty) Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(color: AppColors.bg1, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.borderSubtle)),
                  child: Row(children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [AppColors.accent.withAlpha(40), AppColors.purple.withAlpha(40)]),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(assignee[0].toUpperCase(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.accent)),
                    ),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Assigned to', style: TextStyle(fontSize: 10, color: AppColors.text3)),
                      Text(assignee, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text0)),
                    ]),
                  ]),
                ),
              ),

              // Description
              if (desc.isNotEmpty) Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: AppColors.bg1, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.borderSubtle)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(width: 3, height: 16, decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 10),
                      const Text('Description', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text0)),
                    ]),
                    const SizedBox(height: 14),
                    SelectableText(desc, style: const TextStyle(fontSize: 14, color: AppColors.text1, height: 1.8)),
                  ]),
                ),
              ),

              // Attachments
              if (attachments.isNotEmpty) Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.attach_file_rounded, size: 18, color: AppColors.text2),
                    const SizedBox(width: 6),
                    Text('${attachments.length} Attachment${attachments.length > 1 ? 's' : ''}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text0)),
                  ]),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 180,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: attachments.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, i) {
                        final att = attachments[i];
                        final mime = (att['mimeType'] ?? '').toString();
                        final filename = att['filename'] ?? '';
                        final content = att['content'] ?? '';
                        final isImage = mime.startsWith('image/');
                        final auth = _basicAuth(td);
                        final proxyFull = isImage && content.toString().isNotEmpty
                            ? 'http://localhost:9091/img?url=${Uri.encodeComponent(content.toString())}&auth=$auth'
                            : '';

                        return GestureDetector(
                          onTap: () {
                            if (isImage && proxyFull.isNotEmpty) {
                              showDialog(context: context, builder: (_) => _ImagePreviewDialog(url: proxyFull, filename: filename));
                            } else if (content.toString().isNotEmpty) {
                              launchUrl(Uri.parse(content.toString()), mode: LaunchMode.externalApplication);
                            }
                          },
                          child: Container(
                            width: 200,
                            decoration: BoxDecoration(
                              color: AppColors.bg1,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.borderSubtle),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(children: [
                              Expanded(
                                child: isImage && proxyFull.isNotEmpty
                                  ? Image.network(proxyFull, fit: BoxFit.cover, width: 200,
                                      errorBuilder: (_, __, ___) => Center(child: Icon(Icons.broken_image_rounded, color: AppColors.text3.withAlpha(80), size: 36)))
                                  : Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(_fileIcon(mime), color: AppColors.accent, size: 36),
                                      const SizedBox(height: 6),
                                      Text(mime.split('/').last.toUpperCase(), style: const TextStyle(fontSize: 10, color: AppColors.text3, fontWeight: FontWeight.w600)),
                                    ])),
                              ),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.borderSubtle))),
                                child: Text(filename, style: const TextStyle(fontSize: 12, color: AppColors.text1, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                ]),
              ),

              // Open in Jira
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 36),
                child: SizedBox(width: double.infinity, child: ElevatedButton.icon(
                  onPressed: () => launchUrl(Uri.parse(td.jira!.issueUrl(key)), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16), label: const Text('Open in Jira'),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                )),
              ),
            ]),
          ),
        ),
      ),
      ),
    );
  }

  Widget _metaCard(String emoji, String label, String value, Color c) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withAlpha(25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c), maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.text3)),
      ]),
    ));
  }

  String _basicAuth(TeamData td) {
    final email = td.config.jira?.email ?? '';
    final token = td.config.jira?.token ?? '';
    return base64Encode(utf8.encode('$email:$token'));
  }

  IconData _fileIcon(String mime) {
    if (mime.contains('pdf')) return Icons.picture_as_pdf_rounded;
    if (mime.contains('video')) return Icons.videocam_rounded;
    if (mime.contains('audio')) return Icons.audiotrack_rounded;
    if (mime.contains('zip') || mime.contains('rar')) return Icons.folder_zip_rounded;
    if (mime.contains('text') || mime.contains('document')) return Icons.description_rounded;
    return Icons.attach_file_rounded;
  }

  Future<void> _howToTest(BuildContext context, String key, Map<String, dynamic> f) async {
    if (td.claude == null) return;
    final cached = td.aiCache.plans[key];
    final planContext = cached?.raw ?? '';

    await showDialog(context: context, builder: (_) => _AIPlanDialog(
      ticketKey: key,
      summary: 'How to test: ${f['summary'] ?? ''}',
      description: 'Based on the implementation plan below, tell me exactly how to test this. Include:\n- Manual testing steps\n- What to verify visually\n- Edge cases to check\n- Any API/state scenarios to validate\n\nPrevious implementation plan:\n$planContext',
      type: 'Test Plan',
      priority: f['priority']?['name'] ?? '',
      claude: td.claude!,
      td: td,
    ));
    if (mounted) setState(() {});
  }

  Future<void> _aiPlan(BuildContext context, String key, Map<String, dynamic> f) async {
    if (td.claude == null || td.jira == null) return;

    // Check cache first
    final cached = td.aiCache.plans[key];
    if (cached != null) {
      if (!context.mounted) return;
      await showDialog(context: context, builder: (_) => _AIPlanDialog(ticketKey: key, summary: f['summary'] ?? '', claude: td.claude!, cached: cached, td: td));
      if (mounted) setState(() {});
      return;
    }

    // Fetch full issue details
    String desc = '';
    List<Map<String, String>> imageUrls = [];
    try {
      final full = await td.jira!.getIssue(key);
      final ff = full['fields'] ?? {};
      final rawDesc = ff['description'];
      desc = rawDesc is Map ? _adf(rawDesc) : (rawDesc is String ? rawDesc : '');
      final atts = ff['attachment'] ?? [];
      for (final a in atts) {
        final mime = (a['mimeType'] ?? '').toString();
        final filename = a['filename'] ?? '';
        final content = a['content'] ?? '';
        if (mime.startsWith('image/') && content.toString().isNotEmpty) {
          imageUrls.add({'url': content.toString(), 'filename': filename, 'auth': _basicAuth(td)});
        }
      }
    } catch (_) {}

    if (!context.mounted) return;
    await showDialog(context: context, builder: (_) => _AIPlanDialog(
      ticketKey: key, summary: f['summary'] ?? '', description: desc,
      type: f['issuetype']?['name'] ?? 'Task', priority: f['priority']?['name'] ?? '',
      claude: td.claude!, td: td, images: imageUrls,
    ));
    if (mounted) setState(() {});
  }

  String _adf(dynamic n) {
    if (n is Map) {
      if (n['type'] == 'text') return n['text'] ?? '';
      final b = StringBuffer();
      if (n['type'] == 'paragraph' || n['type'] == 'heading') b.write('\n');
      if (n['type'] == 'listItem') b.write('\u2022 ');
      for (final c in (n['content'] ?? [])) b.write(_adf(c));
      if (n['type'] == 'paragraph' || n['type'] == 'heading' || n['type'] == 'listItem') b.write('\n');
      return b.toString();
    }
    if (n is List) return n.map(_adf).join();
    return '$n';
  }
}

// ── AI Chat Dialog ────────────────────────────────────────────

// ── Image Preview ─────────────────────────────────────────────

class _ImagePreviewDialog extends StatelessWidget {
  final String url;
  final String filename;
  const _ImagePreviewDialog({required this.url, required this.filename});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Stack(children: [
        // Image
        Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.network(url, fit: BoxFit.contain,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2));
              },
              errorBuilder: (_, __, ___) => const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.broken_image_rounded, color: Colors.white38, size: 48),
                SizedBox(height: 8),
                Text('Failed to load image', style: TextStyle(color: Colors.white38)),
              ])),
            ),
          ),
        ),
        // Filename bar
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.transparent, Colors.black.withAlpha(180)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
            ),
            child: Text(filename, style: const TextStyle(color: Colors.white70, fontSize: 13), textAlign: TextAlign.center),
          ),
        ),
        // Close button
        Positioned(
          top: 8, right: 8,
          child: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── AI Chat Dialog ────────────────────────────────────────────

class _AIPlanDialog extends StatefulWidget {
  final String ticketKey, summary;
  final String? description, type, priority;
  final ClaudeService claude;
  final ImplementationPlan? cached;
  final TeamData td;
  final List<Map<String, String>> images;

  const _AIPlanDialog({required this.ticketKey, required this.summary, this.description, this.type, this.priority, required this.claude, this.cached, required this.td, this.images = const []});
  @override
  State<_AIPlanDialog> createState() => _AIPlanDialogState();
}

class _AIPlanDialogState extends State<_AIPlanDialog> {
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
        key: widget.ticketKey, summary: widget.summary,
        description: widget.description ?? '', type: widget.type ?? 'Task', priority: widget.priority ?? '',
        images: widget.images,
        onLog: _appendOutput,
      );
      widget.td.aiCache.plans[widget.ticketKey] = plan;
    } catch (e) {
      _appendOutput('\n\nError: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _sendFollowUp() async {
    final prompt = _promptCtrl.text.trim();
    if (prompt.isEmpty || _busy) return;
    _promptCtrl.clear();

    setState(() {
      _busy = true;
      _output += '\n\n\u2500\u2500\u2500 You \u2500\u2500\u2500\n$prompt\n\n';
    });

    try {
      await widget.claude.sendPrompt(
        prompt: prompt,
        context: _output,
        onLog: _appendOutput,
      );
    } catch (e) {
      _appendOutput('\n\nError: $e');
    }
    if (mounted) {
      setState(() => _busy = false);
      _promptFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1a1b26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 600),
        child: Column(children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            decoration: const BoxDecoration(
              color: Color(0xFF24283b),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.accent, Color(0xFF5856D6)]),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Text('C', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.ticketKey, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFc0caf5))),
                Text(widget.summary, style: const TextStyle(fontSize: 11, color: Color(0xFF565f89)), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              if (_busy)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7aa2f7)))
              else if (widget.cached != null)
                IconButton(icon: const Icon(Icons.refresh_rounded, size: 18, color: Color(0xFF565f89)), onPressed: _runInitial, tooltip: 'Re-run'),
              IconButton(icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF565f89)), onPressed: () => Navigator.pop(context)),
            ]),
          ),

          // Terminal output
          Expanded(
            child: Container(
              width: double.infinity,
              color: const Color(0xFF1a1b26),
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  _output.isEmpty ? (_busy ? 'Starting...' : 'Ready.') : _output,
                  style: TextStyle(
                    fontSize: 13,
                    color: _output.isEmpty ? const Color(0xFF565f89) : const Color(0xFFa9b1d6),
                    fontFamily: 'monospace',
                    height: 1.7,
                  ),
                ),
              ),
            ),
          ),

          // Input bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
            decoration: const BoxDecoration(
              color: Color(0xFF24283b),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Row(children: [
              const Text('\u276F ', style: TextStyle(fontSize: 14, color: Color(0xFF7aa2f7), fontFamily: 'monospace', fontWeight: FontWeight.w700)),
              Expanded(child: TextField(
                controller: _promptCtrl,
                focusNode: _promptFocus,
                enabled: !_busy,
                onSubmitted: (_) => _sendFollowUp(),
                style: const TextStyle(fontSize: 13, color: Color(0xFFc0caf5), fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  hintText: 'Ask a follow-up...',
                  hintStyle: TextStyle(color: Color(0xFF444b6a)),
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
