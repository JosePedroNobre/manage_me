import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import 'common.dart';

class DetailDialog extends StatelessWidget {
  final String serviceLabel;
  final Color accentColor;
  final String title;
  final String? subtitle;
  final String? url;
  final String? description;
  final List<DetailMeta> meta;

  const DetailDialog({
    super.key,
    required this.serviceLabel,
    required this.accentColor,
    required this.title,
    this.subtitle,
    this.url,
    this.description,
    this.meta = const [],
  });

  static Future<void> show(BuildContext context, {
    required String serviceLabel,
    required Color accentColor,
    required String title,
    String? subtitle,
    String? url,
    String? description,
    List<DetailMeta> meta = const [],
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg1,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollCtrl) => DetailDialog(
          serviceLabel: serviceLabel,
          accentColor: accentColor,
          title: title,
          subtitle: subtitle,
          url: url,
          description: description,
          meta: meta,
        )._buildContent(scrollCtrl),
      ),
    );
  }

  Widget _buildContent(ScrollController scrollCtrl) {
    return SingleChildScrollView(
      controller: scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppColors.bg3, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: accentColor.withAlpha(20), borderRadius: BorderRadius.circular(8)),
            child: Text(serviceLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accentColor)),
          ),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text0, height: 1.3)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: const TextStyle(fontSize: 13, color: AppColors.text3)),
          ],
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(spacing: 16, runSpacing: 10, children: meta.map((m) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(m.label.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.text3, letterSpacing: 0.8)),
                const SizedBox(height: 3),
                m.widget ?? Text(m.value ?? '', style: const TextStyle(fontSize: 13, color: AppColors.text1)),
              ],
            )).toList()),
          ],
          if (description != null && description!.isNotEmpty) ...[
            const SizedBox(height: 20),
            const SectionTitle('Description'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.bg0,
                border: Border.all(color: AppColors.borderSubtle),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                _cleanDescription(description!),
                style: const TextStyle(fontSize: 13, color: AppColors.text1, height: 1.6),
              ),
            ),
          ],
          if (url != null) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text('Open in $serviceLabel'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _cleanDescription(String raw) {
    if (raw.trimLeft().startsWith('{')) {
      try { return _extractAdfText(raw); } catch (_) {}
    }
    return raw.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  static String _extractAdfText(String json) {
    return json; // Pre-extracted by service layer
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class DetailMeta {
  final String label;
  final String? value;
  final Widget? widget;
  const DetailMeta({required this.label, this.value, this.widget});
}
