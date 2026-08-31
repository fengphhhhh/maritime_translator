import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/recognition_turn.dart';
import '../models/session_status.dart';
import '../models/speech_direction.dart';
import '../services/pcm_recorder.dart';
import '../theme/night_theme.dart';
import 'marine_card.dart';

/// The centre of the screen. Translation stays at 32pt; source text is larger
/// for quick reference during bridge-to-bridge calls.
class TranscriptStage extends StatelessWidget {
  const TranscriptStage({
    super.key,
    required this.status,
    required this.turn,
    required this.activeDirection,
    required this.elapsed,
    required this.level,
    required this.progress,
    required this.sourceText,
    required this.showSourceFlash,
    required this.errorMessage,
    required this.onDismissError,
  });

  static const double resultFontSize = 32;
  static const double sourceFontSize = 21;
  static const double timingFontSize = 10;

  final SessionStatus status;
  final RecognitionTurn? turn;
  final SpeechDirection? activeDirection;
  final Duration elapsed;
  final double level;
  final int? progress;
  final String? sourceText;
  final bool showSourceFlash;
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
        SessionStatus.translating => _TranslatingView(
          key: ValueKey('translating-$showSourceFlash'),
          direction: activeDirection ?? SpeechDirection.englishToChinese,
          sourceText: sourceText ?? '',
          showSourceFlash: showSourceFlash,
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
    return MarineCard(
      accent: NightPalette.accentGlow,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: NightPalette.accentGlow.withValues(alpha: 0.35),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: NightPalette.accentGlow.withValues(alpha: 0.12),
                  blurRadius: 20,
                ),
              ],
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
            '识别与翻译均在本机运行，无需网络。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: NightPalette.textMuted,
            ),
          ),
        ],
      ),
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

    return MarineCard(
      accent: accent,
      child: Column(
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
      ),
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

    return MarineCard(
      accent: accent,
      child: Column(
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
      ),
    );
  }
}

class _TranslatingView extends StatelessWidget {
  const _TranslatingView({
    super.key,
    required this.direction,
    required this.sourceText,
    required this.showSourceFlash,
  });

  final SpeechDirection direction;
  final String sourceText;
  final bool showSourceFlash;

  @override
  Widget build(BuildContext context) {
    final accent = direction.accent;

    if (showSourceFlash && sourceText.isNotEmpty) {
      return MarineCard(
        accent: accent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: _RoutePill(direction: direction, label: '识别原文'),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  sourceText,
                  style: TextStyle(
                    fontSize: TranscriptStage.sourceFontSize,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: accent.withValues(alpha: 0.95),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return MarineCard(
      accent: accent,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: accent,
              backgroundColor: NightPalette.outline,
            ),
          ),
          const SizedBox(height: 26),
          const Text(
            '正在翻译...',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
              color: NightPalette.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '本机 Qwen 模型 · ${direction.resultLabel}',
            style: const TextStyle(fontSize: 14, color: NightPalette.textMuted),
          ),
          if (sourceText.isNotEmpty) ...[
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                sourceText,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: TranscriptStage.sourceFontSize,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: accent.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({super.key, required this.turn});

  final RecognitionTurn turn;

  @override
  Widget build(BuildContext context) {
    final headline = turn.displayText;
    final hasHeadline = headline.isNotEmpty;
    final accent = turn.direction.accent;

    return MarineCard(
      accent: accent,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _RoutePill(direction: turn.direction),
          ),
          if (turn.hasTranslation && turn.sourceText.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              '原文',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: NightPalette.textMuted,
              ),
            ),
            const SizedBox(height: 6),
            SelectableText(
              turn.sourceText,
              style: TextStyle(
                fontSize: TranscriptStage.sourceFontSize,
                height: 1.45,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.15,
                color: accent.withValues(alpha: 0.95),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '译文',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: NightPalette.textMuted,
              ),
            ),
            const SizedBox(height: 6),
          ] else
            const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                hasHeadline ? headline : '没有识别到语音内容',
                style: TextStyle(
                  fontSize: TranscriptStage.resultFontSize,
                  height: 1.38,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: hasHeadline
                      ? NightPalette.textPrimary
                      : NightPalette.textMuted,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'ASR: ${formatSeconds(turn.asrTime)} | '
                  'LLM: ${formatSeconds(turn.llmTime)} · '
                  '${PcmFormat.description}',
                  style: const TextStyle(
                    fontSize: TranscriptStage.timingFontSize,
                    color: NightPalette.textMuted,
                  ),
                ),
              ),
              if (hasHeadline)
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: headline));
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
      ),
    );
  }
}

class _RoutePill extends StatelessWidget {
  const _RoutePill({required this.direction, this.label});

  final SpeechDirection direction;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final accent = direction.accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.40), width: 1.1),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.10),
            blurRadius: 8,
          ),
        ],
      ),
      child: Text(
        label ?? direction.resultLabel,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
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
        child: MarineCard(
          accent: NightPalette.danger,
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

String formatSeconds(Duration duration) {
  final seconds = duration.inMilliseconds / 1000;
  return '${seconds.toStringAsFixed(1)}s';
}
