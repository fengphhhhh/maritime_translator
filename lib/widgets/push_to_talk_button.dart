import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/speech_direction.dart';
import '../theme/night_theme.dart';

/// One of the two oversized bottom keys.
///
/// Deliberately driven by [Listener] rather than a button widget: the key must
/// arm the moment a finger lands and disarm the moment it leaves, including
/// when the gesture is cancelled by a scroll, a call, or a glove slipping off
/// the glass.
class PushToTalkButton extends StatefulWidget {
  const PushToTalkButton({
    super.key,
    required this.direction,
    required this.isActive,
    required this.isEnabled,
    required this.level,
    required this.onPressStart,
    required this.onPressEnd,
    required this.onPressCancel,
    this.height = 168,
  });

  final SpeechDirection direction;

  /// This key is the one currently recording.
  final bool isActive;

  /// Pressing is allowed (the other key is idle and no turn is being decoded).
  final bool isEnabled;

  /// Microphone loudness, `0..1`, used for the meter and the glow.
  final double level;

  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;
  final VoidCallback onPressCancel;

  final double height;

  @override
  State<PushToTalkButton> createState() => _PushToTalkButtonState();
}

class _PushToTalkButtonState extends State<PushToTalkButton> {
  int? _pointer;

  bool get _isPressed => _pointer != null;

  void _handleDown(PointerDownEvent event) {
    if (!widget.isEnabled || _isPressed) return;
    setState(() => _pointer = event.pointer);
    HapticFeedback.mediumImpact();
    widget.onPressStart();
  }

  void _handleUp(PointerUpEvent event) {
    if (_pointer != event.pointer) return;
    setState(() => _pointer = null);
    HapticFeedback.selectionClick();
    widget.onPressEnd();
  }

  void _handleCancel(PointerCancelEvent event) {
    if (_pointer != event.pointer) return;
    setState(() => _pointer = null);
    widget.onPressCancel();
  }

  @override
  void didUpdateWidget(covariant PushToTalkButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent can veto a press (permission denied, engine busy); drop the
    // local pressed state so the key does not stay lit.
    if (_isPressed && !widget.isEnabled && !widget.isActive) {
      _pointer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.direction.accent;
    final dimmed = !widget.isEnabled && !widget.isActive;

    return Semantics(
      button: true,
      enabled: widget.isEnabled,
      label:
          '${widget.direction.buttonLabel}，${widget.direction.buttonSubtitle}',
      hint: '按住录音，松开开始识别',
      child: Listener(
        onPointerDown: _handleDown,
        onPointerUp: _handleUp,
        onPointerCancel: _handleCancel,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: widget.isActive ? 0.98 : 1,
          duration: const Duration(milliseconds: 110),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: widget.isActive
                    ? [
                        Color.alphaBlend(
                          accent.withValues(alpha: 0.32),
                          NightPalette.surfaceRaised,
                        ),
                        Color.alphaBlend(
                          accent.withValues(alpha: 0.14),
                          NightPalette.surface,
                        ),
                      ]
                    : const [
                        NightPalette.surfaceRaised,
                        NightPalette.surface,
                      ],
              ),
              border: Border.all(
                color: widget.isActive
                    ? accent
                    : accent.withValues(alpha: dimmed ? 0.14 : 0.38),
                width: widget.isActive ? 2.5 : 1.5,
              ),
              boxShadow: widget.isActive
                  ? [
                      BoxShadow(
                        color: accent.withValues(
                          alpha: 0.18 + 0.22 * widget.level,
                        ),
                        blurRadius: 28 + 26 * widget.level,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Opacity(
              opacity: dimmed ? 0.42 : 1,
              child: _ButtonContent(
                direction: widget.direction,
                isActive: widget.isActive,
                level: widget.level,
                compact: widget.height <= 140,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.direction,
    required this.isActive,
    required this.level,
    required this.compact,
  });

  final SpeechDirection direction;
  final bool isActive;
  final double level;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent = direction.accent;
    final circleSize = compact ? 40.0 : 54.0;
    final gap = compact ? 6.0 : 12.0;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: compact ? 10 : 14,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: circleSize,
            height: circleSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? accent : accent.withValues(alpha: 0.14),
            ),
            child: Icon(
              isActive ? Icons.graphic_eq_rounded : Icons.mic_none_rounded,
              size: compact ? 22 : 28,
              color: isActive ? NightPalette.background : accent,
            ),
          ),
          SizedBox(height: gap),
          Text(
            direction.buttonLabel,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: TextStyle(
              fontSize: compact ? 18 : 22,
              height: 1.15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: isActive ? Colors.white : NightPalette.textPrimary,
            ),
          ),
          SizedBox(height: compact ? 3 : 4),
          Text(
            direction.buttonSubtitle,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: TextStyle(
              fontSize: compact ? 11.5 : 12.5,
              height: 1.2,
              letterSpacing: 0.4,
              color: NightPalette.textMuted,
            ),
          ),
          SizedBox(height: gap),
          SizedBox(
            height: 6,
            child: isActive
                ? _LevelMeter(level: level, color: accent)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// Segmented loudness meter: bars light up as the incoming PCM gets louder, so
/// the user can tell the mic is live without watching the transcript.
class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.level, required this.color});

  final double level;
  final Color color;

  static const int _segments = 12;

  @override
  Widget build(BuildContext context) {
    final lit = (level * _segments).round();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_segments, (index) {
        final isLit = index < lit;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: 6,
            height: isLit ? 6 : 3,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: isLit ? color : color.withValues(alpha: 0.18),
            ),
          ),
        );
      }),
    );
  }
}
