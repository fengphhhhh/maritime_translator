import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Ensures shared Documents folders exist so iOS Files shows the app entry.
///
/// With [UIFileSharingEnabled], iOS only lists the app under On My iPhone
/// after the Documents directory exists and contains at least one file.
abstract final class DocumentsBootstrap {
  static const String _modelsReadme = '''
航海英语语音翻译 — 模型目录
========================

安装包不包含模型。请将手机里已有的 Whisper / Qwen 模型文件拷贝到本目录：

  ggml-large-v3-turbo-q5_0.bin
  qwen2.5-1.5b-instruct-q4_k_m.gguf

文件名必须与上面一致，且内容须为对应的完整兼容模型，不能只改其他模型的名称。
拷贝完成后重新打开 App，即可离线识别和翻译，无需重新安装 IPA。
录音文件在 Documents/recordings/。
''';

  static Future<void> ensureSharedFolders() async {
    try {
      final Directory documents = await getApplicationDocumentsDirectory();
      final Directory models = Directory('${documents.path}/models');
      final Directory recordings = Directory('${documents.path}/recordings');

      await models.create(recursive: true);
      await recordings.create(recursive: true);

      final File readme = File('${models.path}/README.txt');
      if (!await readme.exists()) {
        await readme.writeAsString(_modelsReadme, flush: true);
      }
    } on Object catch (error) {
      debugPrint('DocumentsBootstrap: $error');
    }
  }
}
