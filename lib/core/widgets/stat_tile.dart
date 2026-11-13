import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Small labelled number: [label] above a bold [value], optional [caption]
/// below and [icon]. Used for the step breakdown and other dashboards.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.accent = AppColors.primary,
    this.background = AppColors.mint,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  final Color accent;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: accent),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  style: t.labelLarge?.copyWith(color: AppColors.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: t.titleLarge?.copyWith(color: AppColors.text)),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(caption!, style: t.bodySmall?.copyWith(color: AppColors.textMuted)),
          ],
        ],
      ),
    );
  }
}
