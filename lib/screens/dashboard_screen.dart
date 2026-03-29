import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import 'tabs/overview_tab.dart';
import 'tabs/jira_tab.dart';
import 'tabs/github_tab.dart';
import 'tabs/gitlab_tab.dart';
import 'tabs/bitbucket_tab.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  bool _refreshing = false;
  Map<String, dynamic>? _usage;
  Timer? _usageTimer;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _buildTabController(state);
    Future.microtask(() => state.loadAllData());
    _fetchUsage();
    _usageTimer = Timer.periodic(const Duration(seconds: 15), (_) => _fetchUsage());
  }

  void _buildTabController(AppState state) { _tabController = TabController(length: _tabCount(state), vsync: this); }

  int _tabCount(AppState state) {
    final td = state.currentTeam;
    if (td == null) return 1;
    int c = 1;
    if (td.jira != null) c++;
    if (td.github != null) c++;
    if (td.gitlab != null) c += 2; // MRs + Issues
    if (td.bitbucket != null) c++;
    return c;
  }

  List<_TabDef> _tabs(AppState state) {
    final td = state.currentTeam;
    final tabs = <_TabDef>[_TabDef('Overview', Icons.dashboard_rounded, null)];
    if (td == null) return tabs;
    if (td.jira != null) tabs.add(_TabDef('Jira', Icons.task_alt_rounded, td.jiraIssues.length));
    if (td.github != null) tabs.add(_TabDef('GitHub', Icons.code_rounded, td.ghMyPRs.length + td.ghReviewReqs.length + td.ghAssigned.length));
    if (td.gitlab != null) {
      tabs.add(_TabDef('GL MRs', Icons.merge_rounded, td.glMyMRs.length + td.glReviews.length));
      tabs.add(_TabDef('GL Issues', Icons.task_alt_rounded, td.glAssigned.length));
    }
    if (td.bitbucket != null) tabs.add(_TabDef('PRs', Icons.merge_rounded, td.bbPRs.length));
    return tabs;
  }

  List<Widget> _tabViews(AppState state) {
    final td = state.currentTeam;
    final views = <Widget>[const OverviewTab()];
    if (td == null) return views;
    if (td.jira != null) views.add(const JiraTab());
    if (td.github != null) views.add(const GitHubTab());
    if (td.gitlab != null) {
      views.add(const GitLabMRsTab());
      views.add(const GitLabIssuesTab());
    }
    if (td.bitbucket != null) views.add(const BitbucketTab());
    return views;
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await context.read<AppState>().refreshAll();
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _fetchUsage() async {
    try {
      final res = await http.get(Uri.parse('http://localhost:9091/usage')).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200 && mounted) setState(() => _usage = jsonDecode(res.body));
    } catch (_) {
      if (mounted) setState(() => _usage = null);
    }
  }

  @override
  void dispose() { _tabController.dispose(); _usageTimer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, _) {
      if (_tabController.length != _tabCount(state)) { _tabController.dispose(); _buildTabController(state); }
      final tabs = _tabs(state);

      return Scaffold(
        body: Column(children: [
          // Custom top bar
          Container(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8, left: 20, right: 12, bottom: 0),
            decoration: BoxDecoration(
              color: AppColors.bg1,
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(6), blurRadius: 10, offset: const Offset(0, 2))],
            ),
            child: Column(children: [
              // Top row
              Row(children: [
                // Logo
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Text('M', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
                const SizedBox(width: 12),
                // Team selector
                if (state.teams.length > 1)
                  Expanded(child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.bg2, borderRadius: BorderRadius.circular(12)),
                    child: DropdownButtonHideUnderline(child: DropdownButton<int>(
                      value: state.selectedTeamIndex,
                      isExpanded: true,
                      dropdownColor: AppColors.bg1,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text0),
                      icon: const Icon(Icons.unfold_more_rounded, size: 18, color: AppColors.text3),
                      items: state.teams.asMap().entries.map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Row(children: [
                          Text(e.value.config.emoji, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 10),
                          Text(e.value.config.name),
                        ]),
                      )).toList(),
                      onChanged: (v) { if (v != null) state.selectTeam(v); },
                    )),
                  ))
                else if (state.currentTeam != null)
                  Expanded(child: Row(children: [
                    Text(state.currentTeam!.config.emoji, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Text(state.currentTeam!.config.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text0)),
                  ])),
                const Spacer(),
                // Claude usage chip
                GestureDetector(
                  onTap: _usage != null ? () => _showUsageSheet(context) : null,
                  child: _usage != null ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const SizedBox(width: 8),
                      const Icon(Icons.auto_awesome_rounded, size: 13, color: Colors.white),
                      const SizedBox(width: 5),
                      Text('${_usage!['usage_pct'] ?? 0}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.white.withAlpha(30), borderRadius: BorderRadius.circular(8)),
                        child: Text('${_usage!['total_requests'] ?? 0}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                      const SizedBox(width: 2),
                    ]),
                  ) : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(color: AppColors.redSoft, borderRadius: BorderRadius.circular(12)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.cloud_off_rounded, size: 13, color: AppColors.red),
                      SizedBox(width: 5),
                      Text('Bridge off', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.red)),
                    ]),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: _refresh,
                  icon: _refreshing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                    : const Icon(Icons.refresh_rounded, size: 22, color: AppColors.text3),
                ),
                IconButton(
                  onPressed: () => _showSettings(context, state),
                  icon: const Icon(Icons.tune_rounded, size: 22, color: AppColors.text3),
                ),
              ]),
              const SizedBox(height: 12),
              // Tabs
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                padding: EdgeInsets.zero,
                labelPadding: const EdgeInsets.only(right: 24),
                tabs: tabs.map((t) => Tab(
                  height: 40,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(t.icon, size: 16),
                    const SizedBox(width: 6),
                    Text(t.label),
                    if (t.count != null && t.count! > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(10)),
                        child: Text('${t.count}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ],
                  ]),
                )).toList(),
              ),
            ]),
          ),
          // Error bar
          if (state.error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              color: AppColors.redSoft,
              child: Row(children: [
                const Icon(Icons.warning_rounded, size: 16, color: AppColors.red),
                const SizedBox(width: 8),
                Expanded(child: Text(state.error!, style: const TextStyle(fontSize: 12, color: AppColors.red))),
              ]),
            ),
          // Body
          Expanded(
            child: state.currentTeam == null
              ? const Center(child: Text('No teams configured', style: TextStyle(color: AppColors.text3)))
              : state.isLoading && state.currentTeam!.totalItems == 0
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(color: AppColors.accentSurface, borderRadius: BorderRadius.circular(14)),
                      child: const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accent))),
                    ),
                    const SizedBox(height: 16),
                    const Text('Loading...', style: TextStyle(fontSize: 14, color: AppColors.text3)),
                  ]))
                : TabBarView(controller: _tabController, children: _tabViews(state)),
          ),
        ]),
      );
    });
  }

  void _showUsageSheet(BuildContext context) {
    final u = _usage;
    if (u == null) return;
    final recent = (u['claude_recent'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final maxMsg = recent.fold<int>(1, (m, x) => (x['messages'] as int) > m ? x['messages'] as int : m);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bg1,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.bg3, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Row(children: [
            Icon(Icons.auto_awesome_rounded, size: 24, color: AppColors.indigo),
            SizedBox(width: 10),
            Text('Claude Code', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text0, letterSpacing: -0.5)),
          ]),
          const SizedBox(height: 20),
          // Sparkline
          if (recent.isNotEmpty) ...[
            const Text('Last 7 days', style: TextStyle(fontSize: 12, color: AppColors.text3)),
            const SizedBox(height: 8),
            SizedBox(
              height: 60,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: recent.map((d) {
                final h = ((d['messages'] as int) / maxMsg * 48).clamp(4.0, 48.0);
                return Expanded(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Container(height: h, decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)], begin: Alignment.bottomCenter, end: Alignment.topCenter),
                      borderRadius: BorderRadius.circular(6),
                    )),
                    const SizedBox(height: 4),
                    Text((d['date'] as String).substring(5), style: const TextStyle(fontSize: 9, color: AppColors.text3)),
                  ]),
                ));
              }).toList()),
            ),
            const SizedBox(height: 20),
          ],
          // Stats grid
          Row(children: [
            _usageCard('${u['claude_total_messages'] ?? 0}', 'All-time messages', AppColors.indigo),
            const SizedBox(width: 10),
            _usageCard('${u['claude_total_sessions'] ?? 0}', 'Sessions', AppColors.purple),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _usageCard('${u['claude_today_messages'] ?? 0}', 'Today messages', AppColors.blue),
            const SizedBox(width: 10),
            _usageCard('${u['total_requests'] ?? 0}', 'Bridge runs', AppColors.cyan),
          ]),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.green.withAlpha(15), AppColors.green.withAlpha(5)]),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.green.withAlpha(30)),
            ),
            child: const Row(children: [
              Icon(Icons.all_inclusive_rounded, size: 18, color: AppColors.green),
              SizedBox(width: 10),
              Expanded(child: Text('Unlimited usage with your Max plan', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.green))),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _usageCard(String value, String label, Color c) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c.withAlpha(12), c.withAlpha(4)]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withAlpha(25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c, letterSpacing: -1)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.text3)),
      ]),
    ));
  }

  void _showSettings(BuildContext context, AppState state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bg1,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text0)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: () { Navigator.pop(context); Navigator.of(context).pushReplacementNamed('/setup'); },
              icon: const Icon(Icons.edit_rounded, size: 16), label: const Text('Edit Teams'),
            )),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red)),
              onPressed: () async { Navigator.pop(context); await state.clearAll(); if (context.mounted) Navigator.of(context).pushReplacementNamed('/setup'); },
              icon: const Icon(Icons.delete_outline_rounded, size: 16), label: const Text('Clear All'),
            )),
          ]),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }
}

class _TabDef {
  final String label;
  final IconData icon;
  final int? count;
  _TabDef(this.label, this.icon, this.count);
}
