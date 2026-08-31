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
  ///
  /// Only the parts of inference that stay on the CPU are affected while
  /// [useMetal] is on.
  static const int decoderThreads = 4;

  /// Run inference on the iPhone GPU through ggml's Metal backend.
  ///
  /// A turbo-class model on the CPU alone does not fit the few-seconds budget
  /// a bridge conversation allows, which is why `local_plugins/whisper_ggml`
  /// exists: the published plugin is CPU-only on iOS.
  ///
  /// Turn this off to fall back to the CPU/Accelerate backend without a
  /// rebuild — worth trying if a specific device produces garbled transcripts
  /// or runs out of memory under Metal.
  static const bool useMetal = true;

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

  // ---------------------------------------------------------------------------
  // Translation
  // ---------------------------------------------------------------------------

  /// The GGUF instruct model that does the translating.
  static const String llmModelAssetPath =
      'assets/models/qwen2.5-1.5b-instruct-q4_k_m.gguf';

  /// File name the translation model gets on disk.
  static String get llmModelFileName => llmModelAssetPath.split('/').last;

  /// Context window for the translator. One bridge utterance plus the system
  /// prompt fits several times over; a larger window would only cost memory.
  static const int llmContextSize = 1024;

  /// Upper bound on the generated translation. A VHF exchange is a sentence
  /// or two, so this is a runaway guard rather than a real limit.
  static const int llmMaxTokens = 192;

  /// Transformer layers to offload to Metal. 99 means "all of them".
  static const int llmGpuLayers = 99;

  /// Role instruction for the translator, in Qwen's ChatML `system` turn.
  static const String translatorPersona =
      '你是一名精通IMO SMCP（标准海事通信用语）的资深远洋海员。'
      '请严格将输入的文字翻译为规范的航海专业术语。'
      '只输出最终译文，绝对不要输出任何解释、拼音或多余字符。';

  /// Maritime terms and their required renderings, keyed by the English side
  /// in lower case.
  ///
  /// Used twice, and the two uses are why this exists rather than a prompt
  /// alone:
  ///
  /// 1. Injected into the system prompt, so the model is told the mapping
  ///    before it translates. Prevention — and the only thing that catches a
  ///    *wrong* translation. A 1.5B model will otherwise render 右舷
  ///    (starboard) as "port side", which on a bridge is the difference
  ///    between passing clear and colliding.
  /// 2. Applied to the output as a case-insensitive replacement, which
  ///    normalises terms the model left in the source language. Backstop.
  ///
  /// Bare "port" is deliberately absent: it means both "left-hand side" and
  /// "harbour", so replacing it unconditionally would corrupt sentences about
  /// arriving somewhere. The compound forms are unambiguous.
  static const Map<String, String> glossary = {
    'starboard bow': '右舷首',
    'starboard quarter': '右舷尾',
    'starboard side': '右舷',
    'port bow': '左舷首',
    'port quarter': '左舷尾',
    'port side': '左舷',
    'starboard': '右舷',
    'chief officer': '大副',
    'second mate': '二副',
    'underway': '在航',
    'draught': '吃水',
    'fairway': '航道',
    'gangway': '舷梯',
    'dredger': '挖泥船',
    'pilot': '引航员',
    'master': '船长',
    'cpa': '最近会遇距离',
    'tcpa': '到达最近会遇点的时间',
    'ukc': '富余水深',
    'vts': '船舶交通管理中心',
    'ecdis': '电子海图显示与信息系统',
    'aio': '海图附加信息',
  };
}
