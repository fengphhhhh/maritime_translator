import 'package:flutter_test/flutter_test.dart';
import 'package:marine_voice_translator/services/translation_checks.dart';

void main() {
  for (final examples in [
    [
      '我们左对左过。',
      '我们左舷对左舷通过。',
      'We will pass port to port.',
      'Port-to-port passing.',
      'Port to port.',
      'We passed port-to-port.',
      'We will pass each other port to port.',
    ],
    [
      '我们右对右过。',
      '我们右舷对右舷通过。',
      'We will pass starboard to starboard.',
      'Starboard-to-starboard passing.',
      'Starboard to starboard.',
      'We passed starboard-to-starboard.',
      'We will pass each other starboard to starboard.',
    ],
    ['我们左 对 左过。', '我们左舷对左舷通过。', 'We will pass port-to-port.'],
    ['我们右 对 右过。', '我们右舷对右舷通过。', 'We will pass starboard-to-starboard.'],
  ]) {
    test(
      'passing aliases preserve explicit side in both comparison directions: ${examples[0]}',
      () {
        for (final a in examples) {
          for (final b in examples) {
            expect(
              TranslationChecks.preservesCriticalMeaning(a, b),
              isTrue,
              reason: '$a -> $b',
            );
          }
        }
      },
    );
  }

  test(
    'mixed side and opposite passing agreements cannot be silently rewritten',
    () {
      for (final pair in [
        ['我们左对左过。', 'We will pass starboard to starboard.'],
        ['我们右对右过。', 'We will pass port to port.'],
        ['我们左对右过。', 'We will pass port to port.'],
        ['我们左舷对右舷通过。', 'We will pass starboard to starboard.'],
      ]) {
        expect(
          TranslationChecks.preservesCriticalMeaning(pair[0], pair[1]),
          isFalse,
        );
      }
    },
  );

  test('geographic port remains distinct from a passing side', () {
    for (final pair in [
      ['I am entering the port.', '我船正在进港。'],
      ['This port is closed.', '本港已关闭。'],
      ['Port to port delivery is available.', '提供港到港运输。'],
    ]) {
      expect(
        TranslationChecks.preservesCriticalMeaning(pair[0], pair[1]),
        isTrue,
      );
      expect(
        TranslationChecks.preservesCriticalMeaning(pair[1], pair[0]),
        isTrue,
      );
    }
  });
}
