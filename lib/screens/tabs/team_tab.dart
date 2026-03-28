import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

class TeamTab extends StatelessWidget {
  const TeamTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, _) {
      final td = state.currentTeam;
      if (td == null) return const SizedBox.shrink();
      final teamData = td.jiraTeamWork;

      if (teamData == null || teamData['team'] == null || (teamData['team'] as Map).isEmpty) {
        return const EmptyState(icon: '\u{1F465}', message: 'Select a Jira board in the Jira tab to see team activity');
      }

      final team = teamData['team'] as Map<String, dynamic>;
      return ListView(padding: const EdgeInsets.all(16), children: [
        SectionTitle('Sprint: ${teamData['sprint'] ?? ''}'),
        ...team.entries.map((e) => _Swimlane(name: e.key, data: e.value)),
      ]);
    });
  }
}

class _Swimlane extends StatefulWidget {
  final String name;
  final Map<String, dynamic> data;
  const _Swimlane({required this.name, required this.data});
  @override
  State<_Swimlane> createState() => _SwimlaneState();
}

class _SwimlaneState extends State<_Swimlane> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final issues = (widget.data['issues'] as List?) ?? [];
    final avatar = widget.data['avatar'] ?? '';
    final done = issues.where((i) => i['statusCategory'] == 'done').length;
    final inProg = issues.where((i) => i['statusCategory'] == 'indeterminate').length;
    final initials = widget.name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(border: Border.all(color: AppColors.borderSubtle), borderRadius: BorderRadius.circular(12), color: AppColors.bg1),
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Row(children: [
            CircleAvatar(radius: 16, backgroundColor: AppColors.accentSurface,
              backgroundImage: avatar.toString().isNotEmpty ? NetworkImage(avatar.toString()) : null,
              child: avatar.toString().isEmpty ? Text(initials, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accent)) : null),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text0))),
            Text('$done/${issues.length} done \u00B7 $inProg in progress', style: const TextStyle(fontSize: 11, color: AppColors.text3, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            AnimatedRotation(turns: _expanded ? 0.25 : 0, duration: const Duration(milliseconds: 200), child: const Icon(Icons.chevron_right, size: 18, color: AppColors.text3)),
          ])),
        ),
        if (_expanded) Padding(padding: const EdgeInsets.all(8), child: Column(children: issues.map<Widget>((i) {
          final statusCat = i['statusCategory'] ?? '';
          final t = (i['type'] ?? '').toString().toLowerCase();
          final emoji = t.contains('bug') ? '\u{1F41B}' : t.contains('story') ? '\u{1F4D6}' : '\u2022';
          return Padding(padding: const EdgeInsets.only(bottom: 6), child: IssueCard(
            icon: ServiceIcon(label: emoji, bg: AppColors.blueSoft, fg: AppColors.blue),
            title: '${i['key']}: ${i['summary'] ?? ''}',
            onTap: (i['url'] ?? '').toString().isNotEmpty ? () => launchUrl(Uri.parse(i['url'].toString()), mode: LaunchMode.externalApplication) : null,
            meta: [StatusPill(label: i['status']?.toString() ?? '', category: statusCat.toString()), if ((i['priority'] ?? '').toString().isNotEmpty) PriorityDot(priority: i['priority'].toString())],
          ));
        }).toList())),
      ]),
    );
  }
}
