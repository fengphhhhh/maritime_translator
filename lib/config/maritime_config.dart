/// Everything about the ASR stage that is expected to change without touching
/// application code: which model file to load, and which vocabulary to bias
/// the decoder towards.
abstract final class MaritimeConfig {
  // ---------------------------------------------------------------------------
  // Model
  // ---------------------------------------------------------------------------

  /// The ggml model shipped inside the app bundle.
  ///
  /// Swap this for a fine-tuned file by dropping the new `.bin` into
  /// `assets/models/` and changing this one line. `pubspec.yaml` declares the
  /// whole `assets/models/` directory, so no other edit is needed.
  static const String modelAssetPath =
      'assets/models/ggml-large-v3-turbo-q5_0.bin';

  /// File name the model gets on disk, derived from [modelAssetPath].
  static String get modelFileName => modelAssetPath.split('/').last;

  /// Number of decoder threads. Whisper on Apple silicon saturates around the
  /// performance-core count; more threads mostly add scheduling overhead.
  static const int decoderThreads = 4;

  // ---------------------------------------------------------------------------
  // Hotwords
  // ---------------------------------------------------------------------------

  /// Domain vocabulary handed to whisper.cpp as `initial_prompt`.
  ///
  /// Whisper biases decoding towards words that appear here, which is what
  /// keeps "CPA" from coming out as "see PA" and "Draught" from becoming
  /// "draft". Add or remove terms freely — the list is joined into the prompt
  /// at call time.
  ///
  /// Keep it well under whisper's prompt budget (224 tokens); past that the
  /// oldest entries are silently dropped.
  static const List<String> hotwords = [
    'VTS',
    'CPA',
    'TCPA',
    'UKC',
    'ECDIS',
    'AIO',
    'Port Bow',
    'Starboard',
    'Underway',
    'Draught',
    'Anchor',
    'Pilot',
    'Gangway',
    'Fairway',
    'Master',
    'Chief Officer',
    'Second Mate',
    'Dredger',
  ];

  /// Sentence placed before [hotwords] to tell whisper what kind of audio this
  /// is. Whisper also copies the prompt's *style*, so this stays punctuated and
  /// capitalised to keep the transcript readable.
  static const String promptPreamble =
      'Maritime VHF bridge-to-bridge radio communication.';

  /// The exact string passed to whisper.cpp as `whisper_full_params.initial_prompt`.
  static String get initialPrompt =>
      '$promptPreamble Terms used: ${hotwords.join(', ')}.';
}
