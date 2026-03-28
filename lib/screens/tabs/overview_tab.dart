import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final td = state.currentTeam;
        if (td == null) return const EmptyState(icon: '\u{1F4CB}', message: 'No team selected');

        final items = _buildItems(td, state);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              StatCard(value: '${state.totalTasks}', label: 'Open Tasks', color: AppColors.indigo, icon: Icons.task_alt_rounded),
              const SizedBox(width: 12),
              StatCard(value: '${state.totalPRs}', label: 'PRs / MRs', color: AppColors.blue, icon: Icons.code_rounded),
              const SizedBox(width: 12),
              StatCard(value: '${state.totalReviews}', label: 'Reviews', color: AppColors.orange, icon: Icons.rate_review_rounded),
            ]),
            const SizedBox(height: 24),

            // Slack integration placeholder
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [const Color(0xFF4A154B).withAlpha(8), const Color(0xFF4A154B).withAlpha(3)]),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF4A154B).withAlpha(20)),
              ),
              child: Column(children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A154B).withAlpha(15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.chat_bubble_rounded, size: 26, color: Color(0xFF4A154B)),
                ),
                const SizedBox(height: 16),
                const Text('Slack Integration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text0, letterSpacing: -0.3)),
                const SizedBox(height: 6),
                const Text('Team conversations, standups, and notifications — coming soon.', style: TextStyle(fontSize: 14, color: AppColors.text3, height: 1.4), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(color: const Color(0xFF4A154B).withAlpha(10), borderRadius: BorderRadius.circular(12)),
                  child: const Text('Coming soon', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A154B))),
                ),
              ]),
            ),
          ],
        );
      },
    );
  }

  List<_Item> _buildItems(TeamData td, AppState state) {
    final items = <_Item>[];
    for (final pr in td.ghReviewReqs) {
      items.add(_Item(icon: const ServiceIcon(label: '!', bg: AppColors.accentSurface, fg: AppColors.accent), title: pr['title'] ?? '', meta: 'Review PR #${pr['number']}', time: pr['updated_at'], url: pr['html_url'], service: 'GitHub'));
    }
    for (final mr in td.glReviews) {
      items.add(_Item(icon: const ServiceIcon(label: '!', bg: AppColors.yellowSoft, fg: AppColors.yellow), title: mr['title'] ?? '', meta: 'Review MR !${mr['iid']}', time: mr['updated_at'], url: mr['web_url'], service: 'GitLab'));
    }
    for (final pr in td.bbPRs) {
      items.add(_Item(icon: const ServiceIcon(label: 'B', bg: AppColors.blueSoft, fg: AppColors.blue), title: pr['title'] ?? '', meta: 'PR #${pr['id']}', time: pr['updated_on'], url: td.bitbucket?.prUrl(pr['_repo'] ?? '', pr['id'] ?? 0), service: 'Bitbucket'));
    }
    for (final issue in td.jiraIssues.take(10)) {
      final f = issue['fields'] ?? {};
      items.add(_Item(icon: const ServiceIcon(label: '\u2022', bg: AppColors.blueSoft, fg: AppColors.blue), title: '${issue['key']}: ${f['summary'] ?? ''}', meta: '${f['status']?['name'] ?? ''} \u00B7 ${f['priority']?['name'] ?? ''}', time: f['updated'], url: td.jira?.issueUrl(issue['key'] ?? ''), service: 'Jira'));
    }
    for (final issue in td.ghAssigned) {
      items.add(_Item(icon: const ServiceIcon(label: '!', bg: AppColors.greenSoft, fg: AppColors.green), title: '#${issue['number']} ${issue['title'] ?? ''}', meta: 'Assigned', time: issue['updated_at'], url: issue['html_url'], service: 'GitHub'));
    }
    return items;
  }
}

class _Item {
  final Widget icon; final String title, meta, service; final String? time, url;
  _Item({required this.icon, required this.title, required this.meta, this.time, this.url, required this.service});
}
