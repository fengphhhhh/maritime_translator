import '../config/maritime_config.dart';

/// Which way a translation runs.
enum TranslationTarget {
  chinese('中文'),
  english('英文');

  const TranslationTarget(this.label);

  /// How the target language is named to the model, in the user turn.
  final String label;
}

/// Prompt construction and output cleanup for the translation stage.
///
/// Deliberately free of Flutter and FFI imports: this is the part of the
/// pipeline whose behaviour is worth checking against a real model, and
/// `tool/prompt_smoke_test.dart` runs it on the desktop to do exactly that.
abstract final class TranslationPrompt {
  /// Builds the ChatML turn sequence Qwen expects.
  ///
  /// The trailing `<|im_start|>assistant\n` with no closing tag is what makes
  /// the model continue as the assistant instead of predicting another turn.
  static String build(String text, TranslationTarget target) {
    final StringBuffer system = StringBuffer(MaritimeConfig.translatorPersona);

    final String terms = _termInstruction(target);
    if (terms.isNotEmpty) {
      system
        ..write('\n')
        ..write(terms);
    }

    return '<|im_start|>system\n$system<|im_end|>\n'
        '<|im_start|>user\n请将以下文字翻译为${target.label}：$text<|im_end|>\n'
        '<|im_start|>assistant\n';
  }

  /// The glossary rendered in the direction the model is translating.
  ///
  /// Stating it as `source=target` pairs is what keeps left and right the
  /// right way round; without it a 1.5B model confuses 右舷 with "port".
  static String _termInstruction(TranslationTarget target) {
    if (MaritimeConfig.glossary.isEmpty) return '';

    final Iterable<String> pairs = MaritimeConfig.glossary.entries.map(
      (entry) => switch (target) {
        TranslationTarget.chinese => '${entry.key}=${entry.value}',
        TranslationTarget.english => '${entry.value}=${entry.key}',
      },
    );

    return '必须严格使用以下术语对照，不得改写：${pairs.join('；')}。';
  }

  /// Repairs what the model got wrong before the text reaches the screen.
  ///
  /// Two passes: strip the scaffolding a chat model sometimes emits around an
  /// answer, then force every glossary term to its required rendering.
  static String polish(String raw, TranslationTarget target) =>
      _applyGlossary(_strip(raw), target);

  /// Removes leftover ChatML tags, surrounding quotes and the "译文：" style
  /// preamble the model adds when it ignores the "only the translation"
  /// instruction.
  static String _strip(String raw) {
    String text = raw.trim();

    for (final String tag in const ['<|im_end|>', '<|im_start|>', '<|endoftext|>']) {
      final int cut = text.indexOf(tag);
      if (cut >= 0) text = text.substring(0, cut);
    }
    text = text.trim();

    text = text.replaceFirst(
      RegExp(r'^\s*(译文|翻译|Translation)\s*[:：]\s*', caseSensitive: false),
      '',
    );

    // Only strip quotes that wrap the whole line, so a quoted phrase inside a
    // sentence survives.
    final RegExp wrapped = RegExp(r'^([""' "'" r'"])(.*)\1$', dotAll: true);
    final RegExpMatch? match = wrapped.firstMatch(text.trim());
    if (match != null) {
      text = match.group(2) ?? text;
    }

    return text.trim();
  }

  /// Rewrites glossary terms the model left in the source language.
  ///
  /// Longest key first, so "port bow" is consumed before a shorter key could
  /// match part of it. Matching is case-insensitive, and English keys are
  /// bounded by word edges so "pilot" does not fire inside "pilotage".
  static String _applyGlossary(String text, TranslationTarget target) {
    if (text.isEmpty) return text;

    final List<MapEntry<String, String>> entries =
        MaritimeConfig.glossary.entries.toList()..sort(
          (a, b) => b.key.length.compareTo(a.key.length),
        );

    String result = text;
    for (final MapEntry<String, String> entry in entries) {
      final (String from, String to) = switch (target) {
        TranslationTarget.chinese => (entry.key, entry.value),
        TranslationTarget.english => (entry.value, entry.key),
      };
      result = result.replaceAll(_termPattern(from), to);
    }
    return result;
  }

  /// Word boundaries only help for Latin script; Chinese runs together, so
  /// applying `\b` there would never match.
  static RegExp _termPattern(String term) {
    final String escaped = RegExp.escape(term);
    final bool isLatin = RegExp(r'^[A-Za-z0-9 ]+$').hasMatch(term);
    return RegExp(
      isLatin ? '\\b$escaped\\b' : escaped,
      caseSensitive: false,
    );
  }
}
