import 'package:flutter/material.dart';

import 'theme.dart';

/// The brown bar with a serif title (and optional sub-line / "← Back") from the design.
class BrandAppBar extends StatelessWidget implements PreferredSizeWidget {
  const BrandAppBar({super.key, required this.title, this.subtitle, this.back = false});
  final String title;
  final String? subtitle;
  final bool back;

  @override
  Size get preferredSize =>
      Size.fromHeight(back || subtitle != null ? 104 : 80);

  @override
  Widget build(BuildContext context) => Container(
        color: brandBrown,
        padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 12, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (back)
              InkWell(
                onTap: () => Navigator.of(context).maybePop(),
                child: const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text('←  Back', style: TextStyle(fontSize: 13, color: lineColor)),
                ),
              ),
            Text(title, style: serif(26, color: surfaceWarm)),
            if (subtitle != null)
              Text(subtitle!, style: const TextStyle(fontSize: 13, color: lineColor)),
          ],
        ),
      );
}

/// A rounded outlined pill, e.g. "Waiting for the workshop PC".
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, this.color, {super.key, this.fill = false});
  final String label;
  final Color color;
  final bool fill;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: fill ? color : null,
          border: Border.all(color: color, width: 1.2),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: fill ? Colors.white : color,
          ),
        ),
      );
}

/// The pale warm panel used for summaries and key actions.
class WarmCard extends StatelessWidget {
  const WarmCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surfaceWarm,
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );
}

/// The bottom bar holding the one main action of a screen.
class ActionBar extends StatelessWidget {
  const ActionBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: lineColor)),
        ),
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
        child: child,
      );
}
