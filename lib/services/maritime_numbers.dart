/// Deterministic number normalization for common radio numerals, dates and times.
/// This is not an acoustic recognizer. Unknown formats remain subject to review.
abstract final class MaritimeNumbers {
  static const _small = <String, int>{
    'zero': 0,
    'oh': 0,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'niner': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
    'sixteen': 16,
    'seventeen': 17,
    'eighteen': 18,
    'nineteen': 19,
    'twenty': 20,
    'thirty': 30,
    'forty': 40,
    'fifty': 50,
    'sixty': 60,
    'seventy': 70,
    'eighty': 80,
    'ninety': 90,
  };
  static const _months = [
    'january',
    'february',
    'march',
    'april',
    'may',
    'june',
    'july',
    'august',
    'september',
    'october',
    'november',
    'december',
  ];
  static String? _english(String phrase) {
    final words = phrase.toLowerCase().split(RegExp(r'[ -]+'));
    final decimal = words.indexWhere((w) => w == 'point' || w == 'decimal');
    if (decimal >= 0) {
      final whole = _english(words.take(decimal).join(' '));
      final tail = words.skip(decimal + 1).map((w) => _small[w]).toList();
      if (whole == null ||
          tail.isEmpty ||
          tail.any((v) => v == null || v > 9)) {
        return null;
      }
      return '$whole.${tail.join()}';
    }
    final values = words.map((w) => _small[w]).toList();
    if (values.every((v) => v != null && v < 10)) return values.join();
    var total = 0, group = 0;
    for (final word in words) {
      if (word == 'hundred') {
        group = (group == 0 ? 1 : group) * 100;
      } else if (word == 'thousand') {
        total += (group == 0 ? 1 : group) * 1000;
        group = 0;
      } else if (_small.containsKey(word)) {
        group += _small[word]!;
      } else {
        return null;
      }
    }
    return '${total + group}';
  }

  static String? _chinese(String phrase) {
    const digits = {
      '零': 0,
      '〇': 0,
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
      '幺': 1,
    };
    if (phrase.contains('点')) {
      final a = phrase.split('点');
      if (a.length != 2 || a[0].isEmpty || a[1].isEmpty) return null;
      final whole = _chinese(a[0]);
      final tail = a[1].split('').map((c) => digits[c]).toList();
      if (whole == null || tail.any((v) => v == null)) return null;
      return '$whole.${tail.join()}';
    }
    if (!RegExp(r'[十百千万]').hasMatch(phrase)) {
      final a = phrase.split('').map((c) => digits[c]).toList();
      return a.any((v) => v == null) ? null : a.join();
    }
    var total = 0, group = 0, digit = 0;
    for (final c in phrase.split('')) {
      if (digits.containsKey(c)) {
        digit = digits[c]!;
      } else if (c == '万') {
        total += (group + digit) * 10000;
        group = 0;
        digit = 0;
      } else {
        final scale = {'十': 10, '百': 100, '千': 1000}[c];
        if (scale == null) return null;
        group += (digit == 0 ? 1 : digit) * scale;
        digit = 0;
      }
    }
    return '${total + group + digit}';
  }

  static List<String> values(String input) {
    var text = input.toLowerCase().replaceAll('−', '-');
    text = text.replaceAllMapped(
      RegExp(r'(\d)[-—–](?=\d)'),
      (m) => '${m[1]} to ',
    );
    text = text.replaceAll(RegExp(r'\btwice\b|\ba couple of\b'), '2');
    text = text.replaceAll(
      RegExp(r'\bno one\b|\bevery one\b|\bone by one\b'),
      'indefinite',
    );
    text = text.replaceAll(RegExp(r'\b(?:this|that|the small) one\b'), 'item');
    text = text.replaceAll(
      RegExp(r'\b(?:wait|just) a minute\b'),
      'wait a moment',
    );
    text = text.replaceAll('on a day like this', 'in these conditions');
    text = text.replaceAll('next deck', 'next 1 deck');
    text = text.replaceAll(
      RegExp(
        r'\b(?:a|an|last|past) (?=(?:minute|hour|day|metre|meter|ton|knot)\b)',
      ),
      '1 ',
    );
    text = text.replaceAllMapped(RegExp(r'best of (three|five|seven)'), (m) {
      final n = _small[m[1]]!;
      return '$n sets ${n ~/ 2 + 1} wins';
    });
    text = text.replaceAll('january', '1 month');
    if (text.contains('云量') || text.contains('cloud cover')) {
      text = text.replaceAllMapped(RegExp(r'(\d)\s*/\s*8\b'), (m) => m[1]!);
    }
    text = text.replaceAll('一两', '一到两');
    if (RegExp(r'时间|时刻|早上|上午|下午|晚上|凌晨|点[零〇一二两三四五六七八九十\d]+分').hasMatch(text)) {
      text = text.replaceAllMapped(
        RegExp(r'([零〇一二两三四五六七八九十\d]+)点([零〇一二两三四五六七八九十\d]+)分?'),
        (m) {
          final h = int.tryParse(m[1]!) ?? int.tryParse(_chinese(m[1]!) ?? '');
          final minute =
              int.tryParse(m[2]!) ?? int.tryParse(_chinese(m[2]!) ?? '');
          if (h == null || minute == null || h > 23 || minute > 59) {
            return m[0]!;
          }
          return '$h hour $minute minute';
        },
      );
    }
    text = text.replaceAll(RegExp(r'第[一二两三四五六七八九十]+'), 'ordinal');
    text = text.replaceAll(
      RegExp(
        r'一(?:个|名|艘|位|台|只|根|次|种|些|段|切|直|定|起|致|律|般|旦|样|会儿|下|方面|边|小(?!时)|勺|吊)',
      ),
      'indefinite',
    );
    text = text.replaceAll(RegExp(r'一层(?=矿砂|油漆|灰尘)'), 'coating');
    text = text.replaceAll(RegExp(r'一点(?![零〇一二三四五六七八九])'), 'some');
    // A spelled date contributes both month and day, just like 五月三十号.
    for (var i = 0; i < _months.length; i++) {
      text = text.replaceAllMapped(
        RegExp('\\b${_months[i]}\\s+(\\d+)(?:st|nd|rd|th)?\\b'),
        (m) => '${i + 1} month ${m[1]}',
      );
    }
    text = text.replaceAllMapped(
      RegExp(r'\b\d{1,3}(?:,\d{3})+(?:\.\d+)?\b'),
      (m) => m[0]!.replaceAll(',', ''),
    );
    text = text.replaceAll(RegExp(r'\bone and a half\b'), '1.5');
    final words = '${_small.keys.join('|')}|hundred|thousand|point|decimal';
    text = text.replaceAllMapped(
      RegExp('\\b(?:$words)(?:[ -]+(?:$words))*\\b'),
      (m) {
        final phrase = m[0]!;
        if (phrase == 'oh') return phrase;
        if (phrase == 'one' &&
            !RegExp(
              r'^[ -]*(?:(?:or|to)\s+(?:two|three)|(?:nautical\s+)?mile|knot|metre|meter|ton|minute|hour|day|deck|degree|scoop)\b',
            ).hasMatch(text.substring(m.end))) {
          return phrase;
        }
        return _english(phrase) ?? phrase;
      },
    );
    // Clock expressions: 14:00 and 14点 denote the same full-hour time.
    text = text.replaceAllMapped(
      RegExp(r'\b(\d{1,2}):([0-5]\d)\b'),
      (m) => m[2] == '00'
          ? '${m[1]} hour'
          : '${m[1]} hour ${int.parse(m[2]!)} minute',
    );
    text = text.replaceAllMapped(
      RegExp(r'\b(\d{1,2})([0-5]\d)(?=\s+(?:local time|utc))'),
      (m) => m[2] == '00'
          ? '${int.parse(m[1]!)} hour'
          : '${int.parse(m[1]!)} hour ${int.parse(m[2]!)} minute',
    );
    text = text.replaceAllMapped(
      RegExp(r'[零〇一二两三四五六七八九幺十百千万]+(?:点[零〇一二两三四五六七八九幺]+)?'),
      (m) {
        final p = m[0]!, after = text.substring(m.end);
        // Ranks and lexical expressions are not numerical quantities.
        if (RegExp(r'^(副|管轮|机工|切|直|定|起|致|律|般|旦|样|会儿|下|方面|边|些|种)')
            .hasMatch(after)) {
          return p;
        }
        if (!RegExp(
          r'^(?:[年月日号点时分秒度节米吨个名艘位台只根次天倍圈局胜站层勺吊]|海里|小时|分钟|厘米|毫米|千米|公斤|英尺|八分|到|至|和|、|[，,。.!！?？\s]|$)',
        ).hasMatch(after)) {
          return p;
        }
        return _chinese(p) ?? p;
      },
    );
    text = text.replaceAllMapped(
      RegExp(r'(\d+)点半'),
      (m) => '${m[1]} hour 30 minute',
    );
    // Separate decimal fractions from clock notation; only explicit 点钟/时
    // is a clock. For spoken times use 时/分 to avoid 6.30 vs 6:30 ambiguity.
    text = text.replaceAll(RegExp(r'\bminus\s+(?=\d)|负(?=\d)|零下(?=\d)'), '-');
    text = text.replaceAll(RegExp(r'\bplus\s+(?=\d)|正(?=\d)'), '+');
    final result = RegExp(r'[+-]?\d+(?:\.\d+)?')
        .allMatches(text)
        .map((m) => m[0]!)
        .toList();
    result.sort();
    return result;
  }
}
