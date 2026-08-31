import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/session_status.dart';
import '../models/speech_direction.dart';
import '../models/translation_turn.dart';
import '../services/pcm_recorder.dart';
import '../theme/night_theme.dart';

/// The centre of the screen. Whatever it shows, the translated line is the
/// largest thing on the display at 32pt.
class TranslationStage extends StatelessWidget {
  const TranslationStage({
    super.key,
    required this.status,
    required this.turn,
    required this.activeDirection,
    required this.elapsed,
    required this.level,
    required this.errorMessage,
    required this.onDismissError,
  });

  static const double resultFontSize = 32;

  final SessionStatus status;
  final TranslationTurn? turn;
  final SpeechDirection? activeDirection;
  final Duration elapsed;
  final double level;
  final String? errorMessage;
  final VoidCallback onDismissError;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      child: switch (status) {
        SessionStatus.listening => _ListeningView(
          key: const ValueKey('listening'),
          direction: activeDirection ?? SpeechDirection.englishToChinese,
          elapsed: elapsed,
          level: level,
        ),
        SessionStatus.decoding => _DecodingView(
          key: const ValueKey('decoding'),
          direction: activeDirection ?? SpeechDirection.englishToChinese,
        ),
        SessionStatus.failed => _ErrorView(
          key: const ValueKey('failed'),
          message: errorMessage ?? '发生未知错误。',
          onDismiss: onDismissError,
        ),
        SessionStatus.done when turn != null => _ResultView(
          key: const ValueKey('done'),
          turn: turn!,
        ),
        _ => const _IdleView(key: ValueKey('idle')),
      },
    );
  }
}

class _IdleView extends StatelessWidget {
  const _IdleView({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: NightPalette.outline, width: 1.5),
          ),
          child: const Icon(
            Icons.record_voice_over_outlined,
            size: 34,
            color: NightPalette.textMuted,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          '按住下方按键开始对讲',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w600,
            color: NightPalette.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '英汉双向互译，全程在本机运行，无需网络。',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: NightPalette.textMuted,
          ),
        ),
      ],
    );
  }
}

class _ListeningView extends StatelessWidget {
  const _ListeningView({
    super.key,
    required this.direction,
    required this.elapsed,
    required this.level,
  });

  final SpeechDirection direction;
  final Duration elapsed;
  final double level;

  @override
  Widget build(BuildContext context) {
    final accent = direction.accent;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _PulseRing(color: accent, level: level),
        const SizedBox(height: 28),
        Text(
          direction.listeningLabel,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: accent,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _formatElapsed(elapsed),
          style: const TextStyle(
            fontSize: 17,
            fontFeatures: [FontFeature.tabularFigures()],
            color: NightPalette.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '松开按键即开始翻译',
          style: TextStyle(fontSize: 14, color: NightPalette.textMuted),
        ),
      ],
    );
  }
}

class _PulseRing extends StatelessWidget {
  const _PulseRing({required this.color, required this.level});

  final Color color;
  final double level;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 84 + 48 * level,
            height: 84 + 48 * level,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.10 + 0.12 * level),
            ),
          ),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.mic_rounded,
              size: 40,
              color: NightPalette.background,
            ),
          ),
        ],
      ),
    );
  }
}

class _DecodingView extends StatelessWidget {
  const _DecodingView({super.key, required this.direction});

  final SpeechDirection direction;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 42,
          height: 42,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: direction.accent,
            backgroundColor: NightPalette.outline,
          ),
        ),
        const SizedBox(height: 26),
        const Text(
          '离线识别并翻译中',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: NightPalette.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          direction.routeLabel,
          style: const TextStyle(fontSize: 14, color: NightPalette.textMuted),
        ),
      ],
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({super.key, required this.turn});

  final TranslationTurn turn;

  @override
  Widget build(BuildContext context) {
    final accent = turn.direction.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: _RoutePill(direction: turn.direction),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  turn.translatedText,
                  style: const TextStyle(
                    fontSize: TranslationStage.resultFontSize,
                    height: 1.38,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: NightPalette.textPrimary,
                  ),
                ),
                const SizedBox(height: 22),
                Container(height: 1, color: NightPalette.outline),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '原文',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: accent.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SelectableText(
                        turn.recognizedText,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          color: NightPalette.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                '${_formatElapsed(turn.audioDuration)} · ${PcmFormat.description}',
                style: const TextStyle(
                  fontSize: 12,
                  color: NightPalette.textMuted,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: turn.translatedText),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('复制译文'),
              style: TextButton.styleFrom(
                foregroundColor: NightPalette.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RoutePill extends StatelessWidget {
  const _RoutePill({required this.direction});

  final SpeechDirection direction;

  @override
  Widget build(BuildContext context) {
    final accent = direction.accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Text(
        direction.routeLabel,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: accent,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({super.key, required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: NightPalette.danger.withValues(alpha: 0.08),
          border: Border.all(color: NightPalette.danger.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 34,
              color: NightPalette.danger,
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                height: 1.5,
                color: NightPalette.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onDismiss,
              style: TextButton.styleFrom(
                foregroundColor: NightPalette.danger,
              ),
              child: const Text('知道了'),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatElapsed(Duration duration) {
  final seconds = duration.inMilliseconds / 1000;
  if (seconds < 60) return '${seconds.toStringAsFixed(1)} 秒';

  final minutes = duration.inMinutes;
  final remainder = duration.inSeconds % 60;
  return '$minutes 分 ${remainder.toString().padLeft(2, '0')} 秒';
}
