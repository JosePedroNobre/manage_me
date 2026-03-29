import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/detail_dialog.dart';

class BitbucketTab extends StatelessWidget {
  const BitbucketTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, _) {
      final td = state.currentTeam;
      if (td == null) return const SizedBox.shrink();
      return ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [StatCard(value: '${td.bbPRs.length}', label: 'Open PRs')]),
        const SizedBox(height: 24),
        if (td.bbPRs.isNotEmpty) ...[const SectionTitle('Pull Requests'), ...td.bbPRs.map((pr) => _prCard(context, pr, td))]
        else const EmptyState(icon: '\u{1F389}', message: 'No open pull requests'),
      ]);
    });
  }

  Widget _prCard(BuildContext context, dynamic pr, TeamData td) {
    final repo = pr['_repo'] ?? '';
    final repoSlug = pr['_repo_slug'] ?? '';
    final src = pr['source']?['branch']?['name'] ?? '';
    final dst = pr['destination']?['branch']?['name'] ?? '';
    final prId = pr['id'];

    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => DetailDialog.show(context, serviceLabel: 'Bitbucket', accentColor: AppColors.blue,
          title: '#$prId ${pr['title'] ?? ''}', subtitle: '$src \u2192 $dst',
          url: td.bitbucket?.prUrl(repo, prId ?? 0),
          description: pr['description'] ?? '',
          meta: [
            DetailMeta(label: 'Repo', value: repo),
            DetailMeta(label: 'Author', value: pr['author']?['display_name'] ?? ''),
            DetailMeta(label: 'Updated', value: timeAgo(pr['updated_on']?.toString())),
          ]),
        child: Padding(padding: const EdgeInsets.all(14), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const ServiceIcon(label: 'B', bg: AppColors.blueSoft, fg: AppColors.blue),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('#$prId ${pr['title'] ?? ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text0), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  Text(repo, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
                  Text('$src \u2192 $dst', style: const TextStyle(fontSize: 12, color: AppColors.text3)),
                  if (pr['updated_on'] != null) Text(timeAgo(pr['updated_on'].toString()), style: const TextStyle(fontSize: 12, color: AppColors.text3)),
                ]),
              ])),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.text3),
            ]),
            // Action buttons
            const SizedBox(height: 10),
            Row(children: [
              OutlinedButton.icon(
                onPressed: () => _analyzePR(context, pr, td),
                icon: const Icon(Icons.search, size: 16), label: const Text('Analyze'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              if (td.claude != null) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _aiReview(context, pr, td),
                  icon: const Icon(Icons.smart_toy, size: 16), label: const Text('AI Review'),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
            ]),
          ],
        )),
      ),
    ));
  }

  void _analyzePR(BuildContext context, dynamic pr, TeamData td) {
    // Basic analysis — no AI needed
    final description = pr['description'] ?? '';
    final title = pr['title'] ?? '';
    final suggestions = <Map<String, String>>[];

    if (title.length < 10) suggestions.add({'msg': 'PR title is very short — add more context', 'type': 'suggestion'});
    if (description.isEmpty) suggestions.add({'msg': 'No description — consider adding context for reviewers', 'type': 'warning'});
    if (description.contains('TODO') || description.contains('FIXME')) suggestions.add({'msg': 'Description contains TODO/FIXME', 'type': 'todo'});

    showDialog(context: context, builder: (_) => Dialog(
      backgroundColor: AppColors.bg1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
      child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('PR #${pr['id']} Analysis', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text0)),
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

  Future<void> _aiReview(BuildContext context, dynamic pr, TeamData td) async {
    if (td.claude == null || td.bitbucket == null) return;
    final repo = pr['_repo'] ?? '';
    final prId = pr['id'] as int;
    final repoSlug = pr['_repo_slug'] ?? '';

    showDialog(context: context, builder: (_) => _AIReviewDialog(pr: pr, repoSlug: repoSlug, repo: repo, prId: prId, td: td));
  }
}

class _AIReviewDialog extends StatefulWidget {
  final dynamic pr;
  final String repoSlug, repo;
  final int prId;
  final TeamData td;
  const _AIReviewDialog({required this.pr, required this.repoSlug, required this.repo, required this.prId, required this.td});
  @override
  State<_AIReviewDialog> createState() => _AIReviewDialogState();
}

class _AIReviewDialogState extends State<_AIReviewDialog> {
  bool _loading = true;
  String _status = 'Fetching PR diff...';
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
      // Fetch the PR diff from Bitbucket
      final diffUrl = 'https://api.bitbucket.org/2.0/repositories/${widget.td.config.bitbucket!.workspace}/${widget.repoSlug}/pullrequests/${widget.prId}/diff';
      final diffRes = await http.get(Uri.parse(diffUrl), headers: {
        'Authorization': 'Basic ${base64Encode(utf8.encode('${widget.td.config.bitbucket!.email}:${widget.td.config.bitbucket!.token}'))}',
        'Accept': 'text/plain',
      });

      String diffText = '';
      if (diffRes.statusCode == 200) {
        diffText = diffRes.body;
      }

      // Build files list for Claude from the diff
      final files = <Map<String, dynamic>>[];
      if (diffText.isNotEmpty) {
        // Parse unified diff into files
        final fileChunks = diffText.split(RegExp(r'^diff --git', multiLine: true));
        for (final chunk in fileChunks) {
          if (chunk.trim().isEmpty) continue;
          final nameMatch = RegExp(r'b/(.+)$', multiLine: true).firstMatch(chunk);
          final filename = nameMatch?.group(1) ?? 'unknown';
          final additions = RegExp(r'^\+[^+]', multiLine: true).allMatches(chunk).length;
          final deletions = RegExp(r'^-[^-]', multiLine: true).allMatches(chunk).length;
          files.add({'filename': filename, 'additions': additions, 'deletions': deletions, 'patch': chunk.length > 4000 ? chunk.substring(0, 4000) : chunk});
        }
      }

      if (files.isEmpty) {
        files.add({'filename': 'PR diff', 'additions': 0, 'deletions': 0, 'patch': diffText.length > 6000 ? diffText.substring(0, 6000) : diffText});
      }

      setState(() => _status = 'Claude is reviewing ${files.length} files...');

      setState(() => _status = 'Claude is reviewing...');
      final review = await widget.td.claude!.reviewPR(
        prTitle: widget.pr['title'] ?? '',
        prDescription: widget.pr['description'] ?? '',
        files: files,
        onLog: _addChunk,
      );

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
      final url = 'https://api.bitbucket.org/2.0/repositories/${widget.td.config.bitbucket!.workspace}/${widget.repoSlug}/pullrequests/${widget.prId}/comments';
      final headers = {
        'Authorization': 'Basic ${base64Encode(utf8.encode('${widget.td.config.bitbucket!.email}:${widget.td.config.bitbucket!.token}'))}',
        'Content-Type': 'application/json',
      };

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

      // Post inline comments on the specific lines
      for (final c in inlineComments) {
        final res = await http.post(Uri.parse(url), headers: headers, body: jsonEncode({
          'content': {'raw': c['comment']},
          'inline': {'path': c['file'], 'to': c['line']},
        }));
        if (res.statusCode != 201) ok = false;
      }

      // Post general comments as a single comment
      if (generalComments.isNotEmpty) {
        final buf = StringBuffer();
        for (final c in generalComments) {
          buf.writeln('${c['comment']}\n');
        }
        final res = await http.post(Uri.parse(url), headers: headers, body: jsonEncode({'content': {'raw': buf.toString()}}));
        if (res.statusCode != 201) ok = false;
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? 'Review posted to PR #${widget.prId}' : 'Failed to post'),
            backgroundColor: ok ? AppColors.green : AppColors.red),
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
                    Text('${widget.repo} #${widget.prId}', style: const TextStyle(fontSize: 12, color: AppColors.text3)),
                    const SizedBox(height: 12),
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
                        onPressed: _posting || _selected.isEmpty ? null : _postAsComment,
                        icon: _posting ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send, size: 16),
                        label: Text('Post ${_selected.length} comment${_selected.length == 1 ? '' : 's'}'),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    const Text('Comment will be posted under your Bitbucket account', style: TextStyle(fontSize: 11, color: AppColors.text3)),
                  ])),
      ),
    );
  }
}
