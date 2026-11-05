/// Application configuration for models and maritime vocabulary.
library;

import 'maritime_vocabulary.dart';
import 'maritime_asr_vocabulary.dart';
import 'maritime_domain_glossary.dart';

/// Everything about the ASR stage that is expected to change without touching
/// application code: which model file to load, and which vocabulary to bias
/// the decoder towards.
abstract final class MaritimeConfig {
  // ---------------------------------------------------------------------------
  // Model
  // ---------------------------------------------------------------------------

  /// The ggml model shipped inside the app bundle.
  static const String modelAssetPath =
      'assets/models/ggml-large-v3-turbo-q5_0.bin';

  /// File name the model gets on disk, derived from [modelAssetPath].
  static String get modelFileName => modelAssetPath.split('/').last;

  static const int decoderThreads = 4;
  static const bool useMetal = true;

  // ---------------------------------------------------------------------------
  // Hotwords
  // ---------------------------------------------------------------------------

  /// Domain vocabulary handed to whisper.cpp as `initial_prompt`.
  ///
  /// Reference vocabulary from `tool/sources/`. Recognition uses the compact
  /// language-specific prompts below, rather than injecting the whole list.
  static List<String> get hotwords => MaritimeVocabulary.hotwords;

  static const String promptPreamble =
      'Maritime VHF bridge-to-bridge radio communication.';

  // Keep this compact: a long word list loses its leading terms when Whisper
  // clips the prompt to its token budget. Do not feed English prose to Chinese ASR.
  static String get initialPrompt => englishPrompt;
  static const String englishPrompt =
      '$promptPreamble ${MaritimeAsrVocabulary.english}';
  static const String chinesePrompt = MaritimeAsrVocabulary.chinese;

  // ---------------------------------------------------------------------------
  // Translation
  // ---------------------------------------------------------------------------

  static const String llmModelAssetPath =
      'assets/models/qwen2.5-1.5b-instruct-q4_k_m.gguf';

  static String get llmModelFileName => llmModelAssetPath.split('/').last;
  static const int llmContextSize = 4096;
  static const int llmMaxTokens = 512;
  static const int maxTranslationCharacters = 900;
  static const int llmGpuLayers = 99;

  static const String translatorPersona =
      '你是一名精通IMO SMCP（标准海事通信用语）的资深远洋海员。'
      '请严格将输入的文字翻译为规范的航海专业术语。'
      '只输出最终译文，绝对不要输出任何解释、拼音或多余字符。';

  /// Runtime glossary; only entries present in the source are injected.
  ///
  /// This is the curated subset from [MaritimeVocabulary.glossary]. The full
  /// word list lives in [MaritimeVocabulary.wordGlossary]; SMCP sentence pairs
  /// live in [MaritimeVocabulary.vhfCorePhrases] and [MaritimeVocabulary.vtsPhrases].
  static final Map<String, String> _glossary = Map.unmodifiable(
    <String, String>{
      ...MaritimeVocabulary.glossary,
      ...MaritimeDomainGlossary.entries,
    }..remove('over and out'),
  );
  static Map<String, String> get glossary => _glossary;
}
