import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Simple vector logo (icon on a rounded green tile) with the StepUp name.
/// No external assets.
class StepUpLogo extends StatelessWidget {
  const StepUpLogo({super.key, this.size = 72, this.showName = true});

  final double size;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: 'StepUp logo',
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(size * 0.3),
              boxShadow: kCardShadow,
            ),
            child: Icon(Icons.directions_walk_rounded, color: Colors.white, size: size * 0.58),
          ),
        ),
        if (showName) ...[
          const SizedBox(height: 12),
          Text(
            'StepUp',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.text,
                  letterSpacing: -0.5,
                ),
          ),
        ],
      ],
    );
  }
}
