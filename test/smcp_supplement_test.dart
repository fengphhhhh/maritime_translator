import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marine_voice_translator/config/maritime_corpus.dart';
import 'package:marine_voice_translator/config/smcp_supplement.dart';
import 'package:marine_voice_translator/services/corpus_service.dart';
import 'package:marine_voice_translator/services/llm_service.dart';
import 'package:marine_voice_translator/services/translation_checks.dart';

void main() {
  test(
    'all supplement rows have aligned reviewed translations and lineage',
    () {
      final source = jsonDecode(
        File('assets/corpus/smcp_supplement.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final rows = source['entries'] as List;
      expect(rows.length, 437);
      expect(SmcpSupplement.pairs.length, rows.length);
      expect(SmcpSupplement.pairs.map((p) => p.category).toSet().length, 6);
      final keys = <String>{};
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i] as Map<String, dynamic>;
        final pair = SmcpSupplement.pairs[i];
        expect(pair.id, row['id']);
        expect(pair.en, row['en']);
        expect(pair.zh, row['zh']);
        expect(pair.zh, isNotEmpty);
        expect(row['reviewStatus'], 'editorially_reviewed');
        expect(row['sourceRecordIds'], isNotEmpty);
        expect(row['referencePdfPages'], isNotEmpty);
        expect(keys.add(CorpusService.normalize(pair.en)), isTrue);
        expect(CorpusService.lookup(pair.en, englishSource: true), pair.zh);
      }
      final manifest = jsonDecode(
        File('tool/corpus/jmu_selection_manifest.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect((manifest['decisions'] as List).length, 5133);
      expect(manifest['decisionCounts']['selected'], rows.length);
    },
  );

  test('supplement preserves existing lookup results in both directions', () {
    for (final english in [true, false]) {
      final original = <String, Set<String>>{};
      for (final pair in MaritimeCorpus.pairs.where((p) => p.standalone)) {
        final key = CorpusService.normalize(english ? pair.en : pair.zh);
        original.putIfAbsent(key, () => {}).add(english ? pair.zh : pair.en);
      }
      for (final entry in original.entries) {
        expect(
          CorpusService.lookup(entry.key, englishSource: english),
          entry.value.length == 1 ? entry.value.single : null,
          reason: entry.key,
        );
      }
    }
  });

  test(
    'every new pair preserves common numerals and checked critical meanings',
    () {
      for (final pair in SmcpSupplement.pairs) {
        expect(
          TranslationChecks.preservesNumbers(pair.en, pair.zh),
          isTrue,
          reason: pair.id,
        );
        expect(
          TranslationChecks.preservesCriticalMeaning(pair.en, pair.zh),
          isTrue,
          reason: pair.id,
        );
        expect(
          TranslationChecks.preservesCriticalMeaning(pair.zh, pair.en),
          isTrue,
          reason: pair.id,
        );
      }
    },
  );

  test(
    'independent anchor quantities and explicit sides reject changed facts',
    () {
      expect(TranslationChecks.numbers('Walk back port anchor one shackle.'), [
        '1',
      ]);
      expect(
        TranslationChecks.preservesNumbers(
          'Walk back starboard anchor one shackle.',
          '右锚送出两节锚链。',
        ),
        isFalse,
      );
      expect(
        TranslationChecks.preservesCriticalMeaning(
          'Port engines half astern.',
          '右舷主机半速后退。',
        ),
        isFalse,
      );
      expect(
        TranslationChecks.preservesCriticalMeaning(
          'Bow thruster half to starboard.',
          '艏侧推向左半速。',
        ),
        isFalse,
      );
      expect(
        TranslationChecks.preservesCriticalMeaning(
          'Hold on the port cable.',
          '刹住右锚链。',
        ),
        isFalse,
      );
      expect(
        TranslationChecks.preservesCriticalMeaning(
          'List to starboard is increasing.',
          '左舷横倾正在加剧。',
        ),
        isFalse,
      );
      expect(
        TranslationChecks.preservesCriticalMeaning(
          'What is your port of destination?',
          '你船目的港是哪里？',
        ),
        isTrue,
      );
    },
  );

  test('courtesy idioms and real prohibitions have distinct checks', () {
    expect(
      TranslationChecks.preservesCriticalMeaning(
        'Do not hesitate to contact the bridge.',
        '请随时联系驾驶台。',
      ),
      isTrue,
    );
    expect(
      TranslationChecks.preservesCriticalMeaning(
        'Do not enter the pump room without permission.',
        '进入泵舱。',
      ),
      isFalse,
    );
    expect(
      TranslationChecks.preservesCriticalMeaning(
        'Never smoke near the fuel station.',
        '严禁在加油站附近吸烟。',
      ),
      isTrue,
    );
    expect(
      TranslationChecks.preservesCriticalMeaning(
        '严禁在床上吸烟。',
        'You may smoke in bed.',
      ),
      isFalse,
    );
  });

  test(
    'a changed question or condition cannot trigger a supplement command',
    () {
      expect(
        CorpusService.lookup('Let go port anchor?', englishSource: true),
        isNull,
      );
      expect(
        CorpusService.lookup(
          'Do not let go port anchor until ordered.',
          englishSource: true,
        ),
        isNull,
      );
      expect(
        CorpusService.lookup(
          'Walk back starboard anchor two shackles.',
          englishSource: true,
        ),
        isNull,
      );
    },
  );

  test('related examples remain bounded and exclude numeric references', () {
    final examples = CorpusService.examples(
      'Please inspect the hatch covers and report damage.',
      englishSource: true,
    );
    expect(examples, isNotEmpty);
    expect(examples.length, lessThanOrEqualTo(2));
    for (final pair in examples) {
      expect(TranslationChecks.numbers(pair.en), isEmpty);
      expect(TranslationChecks.numbers(pair.zh), isEmpty);
    }
  });

  test(
    'new ventilation and side-thruster pairs use the public offline path',
    () async {
      final service = LlmService();
      expect(
        await service.translate(
          text: 'Switch on the hold ventilation to exhaust air.',
          isEnglishToChinese: true,
        ),
        '启动货舱通风设备进行排风。',
      );
      expect(
        await service.translate(text: '艉侧推向左半速。', isEnglishToChinese: false),
        'Stern thruster half to port.',
      );
      expect(service.isResident, isFalse);
    },
  );
}
