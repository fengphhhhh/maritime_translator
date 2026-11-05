import '../config/maritime_corpus.dart';
import 'maritime_numbers.dart';

/// Entirely local, read-only phrase lookup and bounded example retrieval.
/// Similarity never returns a final translation: only a literal full match can.
abstract final class CorpusService {
  static String normalize(String text) => text
      .toLowerCase()
      .replaceAll('’', "'")
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceFirst(RegExp(r'[.!。！]+$'), '')
      .trim();

  static final _english = _index(true);
  static final _chinese = _index(false);

  static Map<String, Set<String>> _index(bool englishSource) {
    final result = <String, Set<String>>{};
    for (final pair in MaritimeCorpus.pairs.where((p) => p.standalone)) {
      final source = englishSource ? pair.en : pair.zh;
      final target = englishSource ? pair.zh : pair.en;
      result.putIfAbsent(normalize(source), () => <String>{}).add(target);
    }
    return result;
  }

  static String? lookup(String text, {required bool englishSource}) {
    final values = (englishSource ? _english : _chinese)[normalize(text)];
    // Ambiguous source keys are deliberately left to the model/context.
    return values != null && values.length == 1 ? values.single : null;
  }

  static final _tokens = <bool, List<Set<String>>>{
    true: MaritimeCorpus.pairs.map((p) => tokens(p.en, true)).toList(),
    false: MaritimeCorpus.pairs.map((p) => tokens(p.zh, false)).toList(),
  };
  static final _hasNumbers = MaritimeCorpus.pairs
      .map(
        (p) =>
            MaritimeNumbers.values(p.en).isNotEmpty ||
            MaritimeNumbers.values(p.zh).isNotEmpty,
      )
      .toList();

  static Set<String> tokens(String text, bool english) {
    final lower = text.toLowerCase();
    if (english) {
      const stop = {
        'the',
        'a',
        'an',
        'is',
        'are',
        'am',
        'i',
        'we',
        'you',
        'it',
        'this',
        'that',
        'to',
        'of',
        'and',
        'please',
        'sir',
        'our',
        'your',
      };
      return RegExp(r'[a-z]+')
          .allMatches(lower)
          .map((m) => m.group(0)!)
          .where((w) => !stop.contains(w))
          .toSet();
    }
    final result = <String>{};
    for (final m in RegExp(r'[\u4e00-\u9fff]+|[a-z]+').allMatches(lower)) {
      final segment = m.group(0)!;
      if (RegExp(r'^[a-z]+$').hasMatch(segment)) {
        result.add(segment);
      } else {
        for (var i = 0; i + 1 < segment.length; i++) {
          final bigram = segment.substring(i, i + 2);
          if (!const {
            '本船',
            '你船',
            '我们',
            '可以',
            '请问',
            '这个',
            '那个',
          }.contains(bigram)) {
            result.add(bigram);
          }
        }
      }
    }
    return result;
  }

  static String criticalSignature(String text, bool english) {
    final s = text.toLowerCase();
    final negative = english
        ? RegExp(r"\b(no|not|never|cannot|can't|don't|doesn't|won't|without)\b")
              .hasMatch(s)
        : RegExp(r'不|未|无|没|禁止|勿|失控').hasMatch(s);
    final question = english
        ? s.contains('?') ||
              RegExp(
                r'^(what|when|where|who|why|how|can|could|shall|should|do|does|did|is|are|have|has|may|will)\b',
              ).hasMatch(s)
        : s.contains('？') ||
              s.contains('?') ||
              RegExp(r'吗|是否|何时|哪里|多少|如何|什么').hasMatch(s);
    final left = english
        ? RegExp(r'\bport\b|\bleft\b').hasMatch(s)
        : RegExp(r'左舷|左转|向左|左侧').hasMatch(s);
    final right = english
        ? RegExp(r'\bstarboard\b|\bright\b').hasMatch(s)
        : RegExp(r'右舷|右转|向右|右侧').hasMatch(s);
    final ahead = english
        ? RegExp(r'\bahead\b').hasMatch(s)
        : RegExp(r'前进|船首前方').hasMatch(s);
    final astern = english
        ? RegExp(r'\bastern\b').hasMatch(s)
        : RegExp(r'后退|船尾后方').hasMatch(s);
    return '$negative:$question:$left:$right:$ahead:$astern';
  }

  static List<CorpusPair> examples(String text, {required bool englishSource}) {
    if (text.length < 8) return const [];
    final query = tokens(text, englishSource);
    if (query.length < 2) return const [];
    final signature = criticalSignature(text, englishSource);
    final ranked = <(double, CorpusPair)>[];
    for (var i = 0; i < MaritimeCorpus.pairs.length; i++) {
      final pair = MaritimeCorpus.pairs[i];
      final source = englishSource ? pair.en : pair.zh;
      // Numeric examples could leak a different position/speed into the answer.
      // Keep all digit-bearing references in the exact-match path only.
      if (!pair.standalone ||
          source.length > 210 ||
          _hasNumbers[i] ||
          normalize(source) == normalize(text) ||
          criticalSignature(source, englishSource) != signature) {
        continue;
      }
      final candidate = _tokens[englishSource]![i];
      final common = query.intersection(candidate).length;
      if (common < 2) continue;
      final score = 2 * common / (query.length + candidate.length);
      if (score >= 0.48) ranked.add((score, pair));
    }
    ranked.sort((a, b) => b.$1.compareTo(a.$1));
    return ranked.take(2).map((r) => r.$2).toList();
  }
}
