import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StatusPill extends StatelessWidget {
  final String label;
  final String category;
  const StatusPill({super.key, required this.label, this.category = 'todo'});

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    switch (category) {
      case 'done': bg = AppColors.greenSoft; fg = AppColors.green;
      case 'progress' || 'indeterminate': bg = AppColors.blueSoft; fg = AppColors.blue;
      case 'review': bg = AppColors.yellowSoft; fg = AppColors.yellow;
      case 'blocked': bg = AppColors.redSoft; fg = AppColors.red;
      default: bg = AppColors.bg2; fg = AppColors.text2;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

class PriorityDot extends StatelessWidget {
  final String priority;
  const PriorityDot({super.key, required this.priority});
  @override
  Widget build(BuildContext context) {
    final p = priority.toLowerCase();
    final c = p.contains('highest') || p.contains('critical') ? AppColors.red : p.contains('high') ? AppColors.orange : p.contains('medium') ? AppColors.yellow : p.contains('low') ? AppColors.green : AppColors.text3;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Text(priority, style: const TextStyle(fontSize: 12, color: AppColors.text2)),
    ]);
  }
}

class StatCard extends StatelessWidget {
  final String value;
  final String label;
  final Color? color;
  final IconData? icon;
  const StatCard({super.key, required this.value, required this.label, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.accent;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [c.withAlpha(12), c.withAlpha(4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.withAlpha(30)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: c.withAlpha(25), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: c),
            ),
            const SizedBox(height: 12),
          ],
          Text(value, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: c, letterSpacing: -1.5, height: 1)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.text2)),
        ]),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  const SectionTitle(this.title, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12, top: 4),
    child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text1)),
  );
}

class EmptyState extends StatelessWidget {
  final String icon;
  final String message;
  const EmptyState({super.key, required this.icon, required this.message});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(60), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(icon, style: const TextStyle(fontSize: 56)),
      const SizedBox(height: 16),
      Text(message, style: const TextStyle(fontSize: 15, color: AppColors.text3), textAlign: TextAlign.center),
    ])),
  );
}

class IssueCard extends StatefulWidget {
  final Widget icon;
  final String title;
  final List<Widget> meta;
  final VoidCallback? onTap;

  const IssueCard({super.key, required this.icon, required this.title, this.meta = const [], this.onTap});

  @override
  State<IssueCard> createState() => _IssueCardState();
}

class _IssueCardState extends State<IssueCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bg1,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _hovered ? AppColors.accent.withAlpha(80) : AppColors.borderSubtle),
              boxShadow: _hovered ? [
                BoxShadow(color: AppColors.accent.withAlpha(12), blurRadius: 20, offset: const Offset(0, 4)),
                BoxShadow(color: AppColors.accent.withAlpha(6), blurRadius: 6),
              ] : [
                BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              widget.icon,
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text0, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (widget.meta.isNotEmpty) ...[const SizedBox(height: 8), Wrap(spacing: 8, runSpacing: 6, children: widget.meta)],
              ])),
              const SizedBox(width: 8),
              AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                padding: EdgeInsets.only(top: 2, right: _hovered ? 0 : 4),
                child: Icon(Icons.chevron_right_rounded, size: 20, color: _hovered ? AppColors.accent : AppColors.text3),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class ServiceIcon extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const ServiceIcon({super.key, required this.label, required this.bg, required this.fg});
  @override
  Widget build(BuildContext context) => Container(
    width: 42, height: 42,
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
    alignment: Alignment.center,
    child: Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: fg)),
  );
}

String timeAgo(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return '';
  final diff = DateTime.now().difference(DateTime.parse(dateStr));
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return '${diff.inDays ~/ 30}mo ago';
}
