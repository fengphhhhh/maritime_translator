import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/recognition_turn.dart';
import '../models/session_status.dart';
import '../models/speech_direction.dart';
import '../services/pcm_recorder.dart';
import '../theme/night_theme.dart';

/// The centre of the screen. Whatever it shows, the recognised text is the
/// largest thing on the display at 32pt.
class TranscriptStage extends StatelessWidget {
  const TranscriptStage({
    super.key,
    required this.status,
    required this.turn,
    required this.activeDirection,
    required this.elapsed,
    required this.level,
    required this.progress,
    required this.errorMessage,
    required this.onDismissError,
  });

  static const double resultFontSize = 32;

  final SessionStatus status;
  final RecognitionTurn? turn;
  final SpeechDirection? activeDirection;
  final Duration elapsed;
  final double level;

  /// Whisper's progress, 0–100, or `null` before the first report.
  final int? progress;

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
        SessionStatus.recognizing => _RecognizingView(
          key: const ValueKey('recognizing'),
          direction: activeDirection ?? SpeechDirection.englishToChinese,
          progress: progress,
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
          '语音识别在本机 Whisper 模型上运行，无需网络。',
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
          formatDuration(elapsed),
          style: const TextStyle(
            fontSize: 17,
            fontFeatures: [FontFeature.tabularFigures()],
            color: NightPalette.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '松开按键即开始识别',
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

/// Shown between key release and transcript. A turbo-class model on the phone's
/// CPU takes seconds, so this state carries a real percentage rather than an
/// indeterminate spinner.
class _RecognizingView extends StatelessWidget {
  const _RecognizingView({
    super.key,
    required this.direction,
    required this.progress,
  });

  final SpeechDirection direction;
  final int? progress;

  @override
  Widget build(BuildContext context) {
    final accent = direction.accent;
    final percent = progress;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 60,
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  value: percent == null ? null : percent / 100,
                  color: accent,
                  backgroundColor: NightPalette.outline,
                ),
              ),
              if (percent != null)
                Text(
                  '$percent',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: accent,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        const Text(
          '正在识别中...',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
            color: NightPalette.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '本机 Whisper 模型 · ${direction.buttonSubtitle}',
          style: const TextStyle(fontSize: 14, color: NightPalette.textMuted),
        ),
      ],
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({super.key, required this.turn});

  final RecognitionTurn turn;

  @override
  Widget build(BuildContext context) {
    final hasText = turn.text.isNotEmpty;

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
            child: SelectableText(
              hasText ? turn.text : '没有识别到语音内容',
              style: TextStyle(
                fontSize: TranscriptStage.resultFontSize,
                height: 1.38,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: hasText
                    ? NightPalette.textPrimary
                    : NightPalette.textMuted,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                '录音 ${formatDuration(turn.audioDuration)} · '
                '识别 ${formatDuration(turn.inferenceTime)} · '
                '${PcmFormat.description}',
                style: const TextStyle(
                  fontSize: 12,
                  color: NightPalette.textMuted,
                ),
              ),
            ),
            if (hasText)
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: turn.text));
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('复制'),
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
        direction.resultLabel,
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
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: NightPalette.danger.withValues(alpha: 0.08),
            border: Border.all(
              color: NightPalette.danger.withValues(alpha: 0.4),
            ),
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
                  fontSize: 16,
                  height: 1.6,
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
      ),
    );
  }
}

String formatDuration(Duration duration) {
  final seconds = duration.inMilliseconds / 1000;
  if (seconds < 60) return '${seconds.toStringAsFixed(1)} 秒';

  final minutes = duration.inMinutes;
  final remainder = duration.inSeconds % 60;
  return '$minutes 分 ${remainder.toString().padLeft(2, '0')} 秒';
}
