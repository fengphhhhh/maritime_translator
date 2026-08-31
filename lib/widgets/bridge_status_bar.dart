import 'package:flutter/material.dart';

import '../theme/night_theme.dart';

/// Header strip: app identity, offline capture format, and pipeline readiness.
class BridgeStatusBar extends StatelessWidget {
  const BridgeStatusBar({
    super.key,
    required this.hasMicPermission,
    required this.isAsrModelReady,
    required this.isLlmModelReady,
    required this.onRequestPermission,
    this.onOpenHistory,
  });

  final bool hasMicPermission;
  final bool? isAsrModelReady;
  final bool? isLlmModelReady;
  final VoidCallback onRequestPermission;
  final VoidCallback? onOpenHistory;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '航海英语对讲',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: NightPalette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '离线 · 16 kHz · 单声道',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 0.3,
                            color: NightPalette.textMuted.withValues(
                              alpha: 0.95,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.wifi_off_rounded,
                        size: 13,
                        color: NightPalette.accentGlow.withValues(alpha: 0.75),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (onOpenHistory != null) ...[
              const SizedBox(width: 8),
              _HistoryButton(onTap: onOpenHistory!),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _modelChip(label: 'ASR', ready: isAsrModelReady),
            _modelChip(label: 'LLM', ready: isLlmModelReady),
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
        ),
      ],
    );
  }

  Widget _modelChip({required String label, required bool? ready}) {
    return switch (ready) {
      true => _StatusChip(
        icon: Icons.memory_rounded,
        label: '$label 就绪',
        color: NightPalette.online,
      ),
      false => _StatusChip(
        icon: Icons.error_outline_rounded,
        label: '$label 缺失',
        color: NightPalette.danger,
      ),
      null => _StatusChip(
        icon: Icons.hourglass_empty_rounded,
        label: '$label 检查中',
        color: NightPalette.textMuted,
      ),
    };
  }
}

class _HistoryButton extends StatelessWidget {
  const _HistoryButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: NightPalette.surfaceRaised,
            border: Border.all(
              color: NightPalette.accentGlow.withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: NightPalette.accentGlow.withValues(alpha: 0.12),
                blurRadius: 12,
              ),
            ],
          ),
          child: const Padding(
            padding: EdgeInsets.all(10),
            child: Icon(
              Icons.history_rounded,
              size: 22,
              color: NightPalette.accentGlow,
            ),
          ),
        ),
      ),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: color.withValues(alpha: 0.10),
            border: Border.all(color: color.withValues(alpha: 0.36), width: 1.1),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
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
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
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
