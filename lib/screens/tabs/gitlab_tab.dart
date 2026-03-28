import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/detail_dialog.dart';

class GitLabTab extends StatelessWidget {
  const GitLabTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, _) {
      final td = state.currentTeam;
      if (td == null) return const SizedBox.shrink();
      return ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          StatCard(value: '${td.glMyMRs.length}', label: 'My MRs'),
          const SizedBox(width: 10),
          StatCard(value: '${td.glReviews.length}', label: 'Assigned MRs'),
          const SizedBox(width: 10),
          StatCard(value: '${td.glAssigned.length}', label: 'Issues'),
        ]),
        const SizedBox(height: 24),
        if (td.glReviews.isNotEmpty) ...[const SectionTitle('Assigned Merge Requests'), ...td.glReviews.map((mr) => _mrCard(context, mr))],
        if (td.glMyMRs.isNotEmpty) ...[const SectionTitle('My Merge Requests'), ...td.glMyMRs.map((mr) => _mrCard(context, mr))],
        if (td.glAssigned.isNotEmpty) ...[const SectionTitle('Assigned Issues'), ...td.glAssigned.map((i) => _issueCard(context, i))],
        if (td.glReviews.isEmpty && td.glMyMRs.isEmpty && td.glAssigned.isEmpty) const EmptyState(icon: '\u{1F389}', message: 'Nothing here'),
      ]);
    });
  }

  Widget _mrCard(BuildContext context, dynamic mr) {
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: IssueCard(
      icon: const ServiceIcon(label: '\u{1F98A}', bg: AppColors.yellowSoft, fg: AppColors.yellow),
      title: '!${mr['iid']} ${mr['title'] ?? ''}',
      onTap: () => DetailDialog.show(context, serviceLabel: 'GitLab', accentColor: AppColors.yellow,
        title: '!${mr['iid']} ${mr['title'] ?? ''}', subtitle: '${mr['source_branch'] ?? ''} \u2192 ${mr['target_branch'] ?? ''}',
        url: mr['web_url'], description: mr['description'] ?? '',
        meta: [
          DetailMeta(label: 'State', widget: StatusPill(label: mr['state'] ?? '', category: mr['state'] == 'opened' ? 'progress' : 'done')),
          DetailMeta(label: 'Author', value: mr['author']?['name'] ?? ''),
          DetailMeta(label: 'Updated', value: timeAgo(mr['updated_at']?.toString())),
        ]),
      meta: [
        Text('${mr['source_branch'] ?? ''} \u2192 ${mr['target_branch'] ?? ''}', style: const TextStyle(fontSize: 12, color: AppColors.text2)),
        Text(timeAgo(mr['updated_at']?.toString()), style: const TextStyle(fontSize: 12, color: AppColors.text3)),
        if (mr['draft'] == true) const StatusPill(label: 'Draft', category: 'todo'),
      ],
    ));
  }

  Widget _issueCard(BuildContext context, dynamic issue) {
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: IssueCard(
      icon: const ServiceIcon(label: '!', bg: AppColors.greenSoft, fg: AppColors.green),
      title: '#${issue['iid']} ${issue['title'] ?? ''}',
      onTap: () => DetailDialog.show(context, serviceLabel: 'GitLab', accentColor: AppColors.green,
        title: '#${issue['iid']} ${issue['title'] ?? ''}', url: issue['web_url'], description: issue['description'] ?? '',
        meta: [DetailMeta(label: 'Updated', value: timeAgo(issue['updated_at']?.toString()))]),
      meta: [Text(timeAgo(issue['updated_at']?.toString()), style: const TextStyle(fontSize: 12, color: AppColors.text3))],
    ));
  }
}
