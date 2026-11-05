import 'translation_prompt.dart';

/// Fixed commands only. No fuzzy matching: one word can reverse an order.
abstract final class StandardPhrases {
  static const pairs = <String, String>{
    'Hard to port': '左满舵',
    'Hard to starboard': '右满舵',
    'Midships': '正舵',
    'Steady as she goes': '把定',
    'Stand by engine': '主机备车',
    'Stop engine': '主机停车',
    'Man overboard': '有人落水',
    'Abandon ship': '弃船',
    'Say again': '请重复',
    'Over': '完毕，请回答',
    'Out': '通话结束，无需答复',
    'What are your intentions': '你船意图是什么',
    'Do not overtake': '禁止追越',
    'Do not anchor': '禁止抛锚',
  };

  static String normalize(String text) => text
      .trim()
      .toLowerCase()
      .replaceFirst(RegExp(r'[.!?。！？]+$'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  static String? lookup(String text, TranslationTarget target) {
    if (text.contains('?') || text.contains('？')) return null;
    var source = normalize(text);
    if (target == TranslationTarget.chinese) {
      source =
          const {
            'hard-a-port': 'hard to port',
            'hard-a-starboard': 'hard to starboard',
          }[source] ??
          source;
    }
    for (final pair in pairs.entries) {
      final from = target == TranslationTarget.chinese ? pair.key : pair.value;
      if (source == normalize(from)) {
        return target == TranslationTarget.chinese ? pair.value : pair.key;
      }
    }
    return null;
  }
}
