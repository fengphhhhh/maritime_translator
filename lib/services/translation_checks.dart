import 'maritime_numbers.dart';

/// Value-preserving checks for common maritime numeric expressions.
abstract final class TranslationChecks {
  static List<String> numbers(String text) => MaritimeNumbers.values(text);
  static bool preservesNumbers(String source, String result) {
    final a = numbers(source), b = numbers(result);
    return a.length == b.length &&
        List.generate(a.length, (i) => a[i] == b[i]).every((same) => same);
  }

  static Set<String> _sides(String text) {
    final s = text.toLowerCase();
    final result = <String>{};
    // Radio shorthand omits 舷: 左对左 / 右对右 carries the same passing
    // side as 左舷对左舷 / 右舷对右舷. Keep both sides for mixed expressions
    // so 左对右 must not become a same-side passing agreement unnoticed.
    for (final passing in RegExp(
      r'([左右])\s*(?:舷\s*)?对\s*([左右])(?:\s*舷)?',
    ).allMatches(s)) {
      result.add(passing[1] == '左' ? 'left' : 'right');
      result.add(passing[2] == '左' ? 'left' : 'right');
    }
    for (final side in ['port', 'starboard']) {
      final passing = '$side(?:\\s+side)?[- ]+to[- ]+$side(?:\\s+side)?';
      if (RegExp(
            '\\b$side\\s+(side|bow|beam|quarter|anchors?|engines?|cables?|wing|capstan|alongside)\\b',
          ).hasMatch(s) ||
          RegExp('\\bpass(?:ing|ed)?\\s+(?:each other\\s+)?$passing\\b')
              .hasMatch(s) ||
          RegExp('\\b$passing\\s+passing\\b').hasMatch(s) ||
          RegExp('^\\W*$passing\\W*\$').hasMatch(s) ||
          RegExp('\\bhard(?:-a-|\\s+(?:to\\s+)?)$side\\b').hasMatch(s) ||
          RegExp('\\b(?:hard(?:-a-)?|course|turn)\\s+(?:to\\s+)?$side\\b')
              .hasMatch(s) ||
          RegExp(
            '\\b(?:bow|stern)\\s+thruster\\s+(?:full|half)\\s+to\\s+$side\\b',
          ).hasMatch(s) ||
          RegExp('\\b(?:list(?:ing)?|leading)\\s+to\\s+$side\\b').hasMatch(s) ||
          RegExp(
            '\\bwalk\\s+back\\s+$side(?:\\s+anchor)?\\s+(?:one|two|[0-9]+)\\b',
          ).hasMatch(s)) {
        result.add(side == 'port' ? 'left' : 'right');
      }
    }
    if (RegExp(r'左舷|左转|向左|左侧|左锚|左主机|左满舵|左舵').hasMatch(s)) result.add('left');
    if (RegExp(r'右舷|右转|向右|右侧|右锚|右主机|右满舵|右舵').hasMatch(s)) result.add('right');
    return result;
  }

  static Set<String> _engineOrders(String text) {
    final s = text.toLowerCase();
    final result = <String>{};
    const speeds = {'dead slow': '微', 'slow': '慢', 'half': '半', 'full': '全'};
    const directions = {'ahead': '前进', 'astern': '后退'};
    for (final m in RegExp(
      r'\b(dead slow|slow|half|full)\s+(ahead|astern)\b',
    ).allMatches(s)) {
      result.add('${m[1]}:${m[2]}');
    }
    for (final speed in speeds.entries) {
      for (final direction in directions.entries) {
        if (s.contains('${speed.value}速${direction.value}') ||
            s.contains('${direction.value}${speed.value}速')) {
          result.add('${speed.key}:${direction.key}');
        }
      }
    }
    return result;
  }

  /// Limited checks for explicit sides and negative orders, not a complete
  /// semantic validator. Geographic "port" is intentionally not a left side.
  static bool preservesCriticalMeaning(String source, String result) {
    final a = _sides(source), b = _sides(result);
    if (a.isNotEmpty && (a.length != b.length || !a.containsAll(b))) {
      return false;
    }
    final engine = _engineOrders(source),
        translatedEngine = _engineOrders(result);
    if (engine.isNotEmpty &&
        (engine.length != translatedEngine.length ||
            !engine.containsAll(translatedEngine))) {
      return false;
    }
    final sourceAhead = RegExp(
      r'\bpass(?:ing)?\s+ahead\b|从.{0,8}(?:船首|船头|前方|前面).{0,5}通过',
      caseSensitive: false,
    ).hasMatch(source);
    final sourceAstern = RegExp(
      r'\bpass(?:ing)?\s+astern\b|从.{0,8}(?:船尾|后方|后面).{0,5}通过',
      caseSensitive: false,
    ).hasMatch(source);
    if (sourceAhead &&
        !RegExp(
          r'船首|船头|前方|前面|\bpass(?:ing)?\s+(?:ahead|in front)',
          caseSensitive: false,
        ).hasMatch(result)) {
      return false;
    }
    if (sourceAstern &&
        !RegExp(
          r'船尾|后方|后面|\bpass(?:ing)?\s+(?:astern|behind)',
          caseSensitive: false,
        ).hasMatch(result)) {
      return false;
    }
    final orderText = source.replaceAll(
      RegExp(r"\b(?:do not|don't) hesitate to\b", caseSensitive: false),
      '',
    );
    final negativeOrder = RegExp(
      r"\bdo not\b|\bdon't\b|\bnever\b|严禁|禁止|不得|请勿|不要",
      caseSensitive: false,
    ).hasMatch(orderText);
    if (negativeOrder &&
        !RegExp(
          r"\bnot\b|\bnever\b|\bno\b|\bdon't\b|不|勿|严禁|禁止|未|无|没|别",
          caseSensitive: false,
        ).hasMatch(result)) {
      return false;
    }
    return true;
  }
}
