// Can run before flutter pub get.
// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';

import '../lib/config/maritime_config.dart';

// Run before a bundled-model release. Merely including README.md is not enough.
// Header/size checks catch missing files and HTML/LFS pointers, not all corruption.
void main() {
  var failed = false;
  for (final path in [
    MaritimeConfig.modelAssetPath,
    MaritimeConfig.llmModelAssetPath,
  ]) {
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() < 100 * 1024 * 1024) {
      stderr.writeln('MISSING/INCOMPLETE offline model: $path');
      failed = true;
      continue;
    }
    final handle = file.openSync();
    try {
      final header = handle.readSync(4);
      final expected = path.endsWith('.gguf')
          ? [71, 71, 85, 70]
          : [108, 109, 103, 103];
      if (header.length != 4 ||
          List.generate(4, (i) => header[i] != expected[i]).any((v) => v)) {
        stderr.writeln('INVALID model header: $path');
        failed = true;
      } else {
        stdout.writeln('FOUND: $path (${file.lengthSync()} bytes)');
      }
    } finally {
      handle.closeSync();
    }
  }
  if (failed) {
    stderr.writeln(
      'Install the complete models before building an offline-ready IPA.',
    );
    exitCode = 1;
  }
}
