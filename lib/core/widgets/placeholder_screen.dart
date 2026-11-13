import 'package:flutter/material.dart';

import 'state_widgets.dart';

/// TEMPORARY screen for features that are not implemented yet. Feature
/// engineers replace the screens that use it.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title, required this.phase, this.showBack = false});

  final String title;
  final int phase;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), automaticallyImplyLeading: showBack),
      body: SafeArea(
        child: EmptyState(
          icon: Icons.construction_outlined,
          title: 'Coming in phase $phase',
          message: '$title is not available yet.',
        ),
      ),
    );
  }
}
