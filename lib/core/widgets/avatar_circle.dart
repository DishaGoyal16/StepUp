import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Round avatar: network image when [photoUrl] is set and loads, otherwise
/// the initials of [name] on a mint background.
class AvatarCircle extends StatelessWidget {
  const AvatarCircle({super.key, required this.name, this.photoUrl, this.radius = 24});

  final String name;
  final String? photoUrl;
  final double radius;

  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Text(
        initialsOf(name),
        style: TextStyle(
          fontSize: radius * 0.8,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
    final url = photoUrl;
    return Semantics(
      label: 'Avatar of $name',
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: const BoxDecoration(color: AppColors.mint, shape: BoxShape.circle),
        clipBehavior: Clip.antiAlias,
        child: (url == null || url.isEmpty)
            ? fallback
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
                loadingBuilder: (_, child, progress) => progress == null ? child : fallback,
              ),
      ),
    );
  }
}
