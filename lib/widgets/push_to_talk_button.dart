import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/speech_direction.dart';
import '../theme/night_theme.dart';

/// One of the two oversized bottom keys.
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
  final bool isActive;
  final bool isEnabled;
  final double level;
  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;
  final VoidCallback onPressCancel;
  final double height;

  @override
  State<PushToTalkButton> createState() => _PushToTalkButtonState();
}

class _PushToTalkButtonState extends State<PushToTalkButton>
    with SingleTickerProviderStateMixin {
  int? _pointer;
  late final AnimationController _rippleController;

  bool get _isPressed => _pointer != null;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
  }

  @override
  void dispose() {
    _rippleController.dispose();
    super.dispose();
  }

  void _handleDown(PointerDownEvent event) {
    if (!widget.isEnabled || _isPressed) return;
    setState(() => _pointer = event.pointer);
    HapticFeedback.mediumImpact();
    _rippleController
      ..reset()
      ..forward();
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
    if (_isPressed && !widget.isEnabled && !widget.isActive) {
      _pointer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.direction.accent;
    final dimmed = !widget.isEnabled && !widget.isActive;
    final pressed = _isPressed || widget.isActive;
    final scale = pressed ? 0.93 : 1.0;

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
          scale: scale,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: SizedBox(
            height: widget.height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Stack(
                fit: StackFit.expand,
                children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: pressed
                          ? [
                              Color.alphaBlend(
                                accent.withValues(alpha: 0.36),
                                NightPalette.surfaceRaised,
                              ),
                              Color.alphaBlend(
                                accent.withValues(alpha: 0.16),
                                NightPalette.surface,
                              ),
                            ]
                          : const [
                              NightPalette.surfaceRaised,
                              NightPalette.surface,
                            ],
                    ),
                    border: Border.all(
                      color: pressed
                          ? accent
                          : accent.withValues(alpha: dimmed ? 0.16 : 0.42),
                      width: pressed ? 2.5 : 1.4,
                    ),
                    boxShadow: pressed
                        ? [
                            BoxShadow(
                              color: accent.withValues(
                                alpha: 0.22 + 0.24 * widget.level,
                              ),
                              blurRadius: 32 + 28 * widget.level,
                              spreadRadius: 1,
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.08),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                  ),
                ),
                AnimatedBuilder(
                  animation: _rippleController,
                  builder: (context, child) {
                    if (_rippleController.value == 0 && !pressed) {
                      return const SizedBox.shrink();
                    }

                    final ripple = pressed
                        ? 0.35 + 0.25 * (1 - _rippleController.value)
                        : 0;

                    return Center(
                      child: Container(
                        width: widget.height * (0.55 + 0.35 * ripple),
                        height: widget.height * (0.55 + 0.35 * ripple),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.withValues(alpha: 0.10 * ripple),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.22 * ripple),
                            width: 1.5,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Opacity(
                  opacity: dimmed ? 0.42 : 1,
                  child: _ButtonContent(
                    direction: widget.direction,
                    isActive: widget.isActive,
                    level: widget.level,
                    compact: widget.height <= 140,
                  ),
                ),
              ],
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
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.45),
                        blurRadius: 16,
                      ),
                    ]
                  : null,
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
