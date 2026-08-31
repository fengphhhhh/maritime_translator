import 'package:flutter/material.dart';

import '../theme/night_theme.dart';

/// Shared card shell for transcript, history, and error surfaces.
class MarineCard extends StatelessWidget {
  const MarineCard({
    super.key,
    required this.child,
    this.accent,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final Color? accent;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final glow = accent ?? NightPalette.english;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            NightPalette.surfaceRaised,
            NightPalette.surface,
          ],
        ),
        border: Border.all(
          color: glow.withValues(alpha: 0.28),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: glow.withValues(alpha: 0.10),
            blurRadius: 24,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
