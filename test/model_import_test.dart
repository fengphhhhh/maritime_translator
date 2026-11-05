import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marine_voice_translator/config/maritime_config.dart';
import 'package:marine_voice_translator/services/documents_bootstrap.dart';
import 'package:marine_voice_translator/services/model_locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory scratch;
  late Directory documents;

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('maritime-model-import-');
    documents = Directory('${scratch.path}/Documents');
    await documents.create();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return switch (call.method) {
            'getApplicationDocumentsDirectory' => documents.path,
            'getApplicationSupportDirectory' => '${scratch.path}/Support',
            _ => throw MissingPluginException(),
          };
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    // Only remove the temporary directory created by this test.
    if (scratch.parent.resolveSymbolicLinksSync() !=
            Directory.systemTemp.resolveSymbolicLinksSync() ||
        !scratch.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last
            .startsWith('maritime-model-import-')) {
      throw StateError('Unexpected temporary directory');
    }
    await scratch.delete(recursive: true);
  });

  test(
    'Creates the shared model folder and resolves both local imports',
    () async {
      await DocumentsBootstrap.ensureSharedFolders();
      expect(File('${documents.path}/models/README.txt').existsSync(), isTrue);
      for (final asset in [
        MaritimeConfig.modelAssetPath,
        MaritimeConfig.llmModelAssetPath,
      ]) {
        final file = File('${documents.path}/models/${asset.split('/').last}');
        // Sparse fixtures exercise file routing and preflight, not model inference.
        final handle = await file.open(mode: FileMode.write);
        try {
          await handle.writeFrom(
            asset.endsWith('.gguf') ? [71, 71, 85, 70] : [108, 109, 103, 103],
          );
          await handle.truncate(100 * 1024 * 1024);
        } finally {
          await handle.close();
        }
        expect(await ModelLocator.locate(asset), file.path);
      }
    },
  );

  test(
    'An empty installation reports a missing model without bundled weights',
    () async {
      await expectLater(
        ModelLocator.locate(MaritimeConfig.modelAssetPath),
        throwsA(isA<ModelMissingException>()),
      );
    },
  );

  test('Rejects an incomplete imported model', () async {
    await DocumentsBootstrap.ensureSharedFolders();
    final name = MaritimeConfig.llmModelAssetPath.split('/').last;
    await File('${documents.path}/models/$name').writeAsBytes([71, 71, 85, 70]);
    await expectLater(
      ModelLocator.locate(MaritimeConfig.llmModelAssetPath),
      throwsA(isA<ModelInvalidException>()),
    );
  });
}
