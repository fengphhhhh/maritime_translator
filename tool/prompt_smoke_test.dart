// Runs the real translation prompt against a real model, on this machine.
//
// iOS cannot be built outside macOS, but the prompt, the glossary and the
// output cleanup are plain Dart, and they are the part most likely to be
// wrong in a way no unit test would catch. This imports the same code the app
// ships and prints what the model actually replies, so a prompt change can be
// judged before it reaches a phone.
//
//   local_plugins/llama_ggml/tool/build_desktop.sh
//   LLAMA_GGML_LIBRARY=local_plugins/llama_ggml/build/desktop/libllama_ggml.so \
//     dart run tool/prompt_smoke_test.dart ~/models/qwen2.5-1.5b-instruct-q4_k_m.gguf
//
// A desktop build is CPU-only and unoptimised, so the timings here say
// nothing about the phone. Judge the wording, not the clock.

import 'dart:io';

import 'package:llama_ggml/llama_ggml.dart';
import 'package:marine_voice_translator/config/maritime_config.dart';
import 'package:marine_voice_translator/services/translation_prompt.dart';

/// Cases chosen for the terms a small model tends to get wrong: the ones
/// where a mistranslation changes which way a ship turns.
const List<(String, TranslationTarget)> _cases = [
  ('Vessel on my port bow, what are your intentions?', TranslationTarget.chinese),
  (
    'CPA is zero point five nautical miles, I will alter course to starboard.',
    TranslationTarget.chinese,
  ),
  ('UKC is insufficient, request pilot assistance.', TranslationTarget.chinese),
  ('请注意，本船富余水深不足，需要引航员协助。', TranslationTarget.english),
  ('右舷有渔船作业，我船将减速避让。', TranslationTarget.english),
  ('左舷首方向有挖泥船在航道内作业。', TranslationTarget.english),
];

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/prompt_smoke_test.dart <model.gguf>');
    exitCode = 64;
    return;
  }

  stdout.writeln('backends : ${await LlamaSession.devices()}');
  stdout.writeln('glossary : ${MaritimeConfig.glossary.length} terms\n');

  final LlamaSession session = await LlamaSession.load(
    args.first,
    contextSize: MaritimeConfig.llmContextSize,
    // A desktop build has no Metal backend to offload to.
    gpuLayers: 0,
  );

  for (final (String text, TranslationTarget target) in _cases) {
    final Stopwatch timer = Stopwatch()..start();
    final String raw = await session.generate(
      TranslationPrompt.build(text, target),
      maxTokens: MaritimeConfig.llmMaxTokens,
    );
    timer.stop();

    final String polished = TranslationPrompt.polish(raw, target);
    stdout.writeln('in    : $text');
    stdout.writeln('raw   : ${raw.trim()}');
    if (polished != raw.trim()) {
      stdout.writeln('fixed : $polished');
    }
    stdout.writeln('time  : ${timer.elapsedMilliseconds} ms\n');
  }

  await session.release();
}
