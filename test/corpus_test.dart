import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marine_voice_translator/config/maritime_corpus.dart';
import 'package:marine_voice_translator/services/corpus_service.dart';
import 'package:marine_voice_translator/services/translation_checks.dart';
import 'package:marine_voice_translator/services/translation_prompt.dart';
import 'package:marine_voice_translator/services/llm_service.dart';

void main() {
  test('all original locations have a non-empty revised bilingual pair', () {
    final source = jsonDecode(
      File('assets/corpus/maritime_dialogues.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final topics = source['data'] as List;
    expect(topics.length, 50);
    var count = 0;
    for (final dynamic topic in topics) {
      for (final dynamic line in topic['lines']) {
        expect((line['en'] as String).trim(), isNotEmpty);
        expect((line['cn'] as String).trim(), isNotEmpty);
        expect(line['reviewStatus'], 'revised');
        count++;
      }
    }
    expect(count, 1176);
    final turns = jsonDecode(
      File('assets/corpus/maritime_turns.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final coverage = <String>{};
    for (final dynamic pair in turns['pairs']) {
      for (final dynamic line in pair['sourceLines']) {
        expect(coverage.add('${pair['topicId']}:$line'), isTrue);
      }
    }
    expect(coverage.length, 1176);
    expect(MaritimeCorpus.pairs.length, (turns['pairs'] as List).length);
  });

  test('corrected domain meanings are available in both directions', () {
    expect(
      CorpusService.lookup('May I take over the watch?', englishSource: true),
      '我可以接班了吗？',
    );
    expect(
      CorpusService.lookup('我可以接班了吗？', englishSource: false),
      'May I take over the watch?',
    );
    expect(
      CorpusService.lookup(
        'Engine room, this is bridge. Finished with engines.',
        englishSource: true,
      ),
      '机舱，这里是驾驶台。完车。',
    );
    expect(
      CorpusService.lookup(
        'Can you tighten the lashing bars in Bay No. 3?',
        englishSource: true,
      ),
      '请把3号贝位的绑扎杆紧固一下，好吗？',
    );
    expect(
      CorpusService.lookup(
        'Never decide on your own that the operation is safe.',
        englishSource: true,
      ),
      '不要擅自认定作业已经安全。',
    );
  });

  test('questions and changed conditions do not execute a nearest command', () {
    expect(CorpusService.lookup('Stop engine?', englishSource: true), isNull);
    expect(
      CorpusService.lookup(
        'Do not stop engine unless ordered.',
        englishSource: true,
      ),
      isNull,
    );
    expect(
      CorpusService.lookup(
        'Go hard to port if it is safe.',
        englishSource: true,
      ),
      isNull,
    );
  });

  test('all standalone corpus references preserve normalized numbers', () {
    for (final pair in MaritimeCorpus.pairs.where((p) => p.standalone)) {
      expect(
        TranslationChecks.preservesNumbers(pair.en, pair.zh),
        isTrue,
        reason: pair.id,
      );
    }
  });

  test('independent radio numeral and time examples', () {
    const cases = [
      (
        'Course one-zero-seven degrees, speed twelve point five knots.',
        '航向107度，航速12.5节。',
      ),
      (
        'Position four-two degrees three-five minutes north, zero-zero-seven degrees two-one minutes west.',
        '北纬42度35分，西经007度21分。',
      ),
      (
        'Change to channel one-two. Distance two decimal five nautical miles.',
        '转到12频道，距离2.5海里。',
      ),
      ('ETA one-four-three-zero local time.', '预计当地时间14:30抵达。'),
      ('当地时间十四点三十分。', 'Local time 14:30.'),
      ('Wave height 2-3 metres.', '浪高2到3米。'),
      ('Temperature minus two decimal five degrees.', '温度负2.5度。'),
    ];
    for (final c in cases) {
      expect(
        TranslationChecks.preservesNumbers(c.$1, c.$2),
        isTrue,
        reason: c.$1,
      );
    }
    expect(
      TranslationChecks.preservesNumbers(
        'Course one-zero-seven degrees.',
        '航向170度。',
      ),
      isFalse,
    );
    expect(
      TranslationChecks.preservesNumbers('Course 007 degrees.', '航向7度。'),
      isFalse,
    );
    expect(
      TranslationChecks.preservesNumbers(
        'The distance is 12.5 nautical miles.',
        '距离12海里。',
      ),
      isFalse,
    );
    expect(
      TranslationChecks.preservesNumbers(
        'Temperature -2.5 degrees.',
        '温度2.5度。',
      ),
      isFalse,
    );
  });

  test('side and prohibition changes are rejected', () {
    expect(
      TranslationChecks.preservesCriticalMeaning('Hard-a-port.', '右满舵。'),
      isFalse,
    );
    expect(
      TranslationChecks.preservesCriticalMeaning('Half astern.', '全速后退。'),
      isFalse,
    );
    expect(
      TranslationChecks.preservesCriticalMeaning('Dead slow ahead.', '微速前进。'),
      isTrue,
    );
    expect(
      TranslationChecks.preservesCriticalMeaning(
        'Keep to the starboard side of the channel.',
        '靠航道右侧航行。',
      ),
      isTrue,
    );
    expect(
      TranslationChecks.preservesCriticalMeaning(
        'I will turn to starboard and pass port to port.',
        '我将右转并左舷对左舷通过。',
      ),
      isTrue,
    );
    expect(
      TranslationChecks.preservesCriticalMeaning(
        'Do not pass ahead of us.',
        '不要追越我船。',
      ),
      isFalse,
    );
    expect(
      TranslationChecks.preservesCriticalMeaning(
        'Do not pass ahead of us.',
        '不要从我船船首前方通过。',
      ),
      isTrue,
    );
    expect(
      TranslationChecks.preservesCriticalMeaning(
        '从我船船尾后方通过。',
        'Pass ahead of us.',
      ),
      isFalse,
    );
    expect(
      TranslationChecks.preservesCriticalMeaning(
        'Alter course to starboard.',
        '向左转向。',
      ),
      isFalse,
    );
    expect(
      TranslationChecks.preservesCriticalMeaning(
        'Alter course to starboard.',
        '向右转向。',
      ),
      isTrue,
    );
    expect(
      TranslationChecks.preservesCriticalMeaning('Do not overtake.', '请追越。'),
      isFalse,
    );
    expect(
      TranslationChecks.preservesCriticalMeaning('Do not overtake.', '不要追越。'),
      isTrue,
    );
    expect(
      TranslationChecks.preservesCriticalMeaning(
        'The next port is Ningbo.',
        '下一港是宁波。',
      ),
      isTrue,
    );
  });

  test(
    'retrieved examples agree on polarity and side and contain no numbers',
    () {
      expect(
        CorpusService.examples(
          'Please show me the emergency generator test records.',
          englishSource: true,
        ),
        isNotEmpty,
      );
      for (final source in [
        'Do not overtake on my starboard side.',
        'I will reduce speed and alter course to port.',
      ]) {
        final examples = CorpusService.examples(source, englishSource: true);
        expect(examples.length, lessThanOrEqualTo(2));
        for (final p in examples) {
          expect(
            CorpusService.criticalSignature(p.en, true),
            CorpusService.criticalSignature(source, true),
          );
          expect(TranslationChecks.numbers(p.en), isEmpty);
          expect(TranslationChecks.numbers(p.zh), isEmpty);
        }
      }
      final p = TranslationPrompt.build(
        'Please spell your vessel name and call sign.',
        TranslationTarget.chinese,
      );
      expect('<|im_start|>'.allMatches(p).length, 3);
      expect(p.length, lessThan(3500));
    },
  );

  test(
    'application translation path uses the local corpus without model loading',
    () async {
      final service = LlmService();
      expect(
        await service.translate(
          text: 'May I take over the watch?',
          isEnglishToChinese: true,
        ),
        '我可以接班了吗？',
      );
      expect(service.isResident, isFalse);
    },
  );
}
