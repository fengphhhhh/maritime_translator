import 'package:flutter/material.dart';

import '../services/pcm_recorder.dart';
import '../theme/night_theme.dart';

/// Header strip: what the app is, that it is offline on purpose, and whether
/// the microphone is actually usable.
class BridgeStatusBar extends StatelessWidget {
  const BridgeStatusBar({
    super.key,
    required this.hasMicPermission,
    required this.onRequestPermission,
  });

  final bool hasMicPermission;
  final VoidCallback onRequestPermission;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '航海英语对讲',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: NightPalette.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                PcmFormat.description,
                style: const TextStyle(
                  fontSize: 11.5,
                  letterSpacing: 0.4,
                  color: NightPalette.textMuted,
                ),
              ),
            ],
          ),
        ),
        const _StatusChip(
          icon: Icons.wifi_off_rounded,
          label: '离线运行',
          color: NightPalette.online,
        ),
        const SizedBox(width: 8),
        if (hasMicPermission)
          const _StatusChip(
            icon: Icons.mic_rounded,
            label: '麦克风就绪',
            color: NightPalette.online,
          )
        else
          _StatusChip(
            icon: Icons.mic_off_rounded,
            label: '开启麦克风',
            color: NightPalette.danger,
            onTap: onRequestPermission,
          ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: color.withValues(alpha: 0.10),
            border: Border.all(color: color.withValues(alpha: 0.32)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
