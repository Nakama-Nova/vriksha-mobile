import 'package:flutter/material.dart';

import '../notices.dart';
import '../shop_status.dart';
import '../theme.dart';
import '../widgets.dart';

/// The list of what the shop wants you to know, and the app-update card when one is out.
class NoticesScreen extends StatelessWidget {
  const NoticesScreen({super.key, required this.status, this.onOpen});
  final ShopStatus status;
  final void Function(Notice)? onOpen; // a notice about a scan opens the Scans tab

  static IconData iconFor(String kind) => switch (kind) {
        'order_web' => Icons.shopping_bag_outlined,
        'payment' => Icons.payments_outlined,
        'low_stock' => Icons.inventory_2_outlined,
        'scan_done' => Icons.view_in_ar,
        'scan_failed' => Icons.error_outline,
        _ => Icons.notifications_none,
      };

  /// "14:05" today, otherwise "27 Oct 14:05".
  static String when(String iso, {DateTime? now}) {
    final at = DateTime.tryParse(iso)?.toLocal();
    if (at == null) return '';
    final today = now ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final time = '${two(at.hour)}:${two(at.minute)}';
    if (at.year == today.year && at.month == today.month && at.day == today.day) return time;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${at.day} ${months[at.month - 1]} $time';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: status,
        builder: (context, _) {
          final recent = status.state.recent;
          final update = status.update;
          return Scaffold(
            backgroundColor: Colors.white,
            appBar: const BrandAppBar(title: 'Alerts'),
            body: ListView(padding: const EdgeInsets.all(20), children: [
              if (update != null) ...[
                WarmCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Update available: ${update.version}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (update.notes.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(update.notes, style: const TextStyle(fontSize: 13, color: textMuted)),
                    ],
                    const SizedBox(height: 10),
                    Row(children: [
                      FilledButton(
                        onPressed: status.openUpdate,
                        child: Text('Download (${update.sizeLabel})'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(onPressed: status.putOffUpdate, child: const Text('Later')),
                    ]),
                  ]),
                ),
                const SizedBox(height: 12),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Notify me on this phone'),
                subtitle: const Text('Website orders, money received, low stock, finished 3D scans. '
                    'Checked about every 15 minutes when the app is closed.',
                    style: TextStyle(fontSize: 12)),
                value: status.state.popups,
                onChanged: status.setPopups,
              ),
              const Divider(),
              if (recent.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text('Nothing new yet.', style: TextStyle(color: textMuted)),
                  ),
                ),
              for (final n in recent)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(iconFor(n.kind), color: brandGold),
                  title: Text(n.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text('${n.body}  ·  ${when(n.createdAt)}'),
                  onTap: onOpen == null ? null : () => onOpen!(n),
                ),
            ]),
          );
        },
      );
}
