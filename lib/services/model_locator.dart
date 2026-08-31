import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:path_provider/path_provider.dart';

/// The model file is not installed. Retrying will not help; the file has to
/// be put on the device.
class ModelMissingException implements Exception {
  const ModelMissingException(this.fileName);

  final String fileName;

  @override
  String toString() => 'ModelMissingException: $fileName';
}

/// Finds the large model files the ASR and translation stages load.
///
/// Both models are hundreds of megabytes to a gigabyte, so the rules are the
/// same for each and live here rather than in either service.
abstract final class ModelLocator {
  /// Resolves [assetPath] to a readable file, in order of preference:
  ///
  /// 1. `Documents/models/` — a file dropped in over the Files app, which
  ///    lets a fine-tuned or smaller model replace the bundled one without a
  ///    rebuild.
  /// 2. The asset inside the installed `.app` bundle, read in place. Avoiding
  ///    a second copy of a gigabyte-scale file is worth the path arithmetic.
  /// 3. A copy extracted from the Flutter asset bundle into Application
  ///    Support, for when the bundle layout is not what step 2 expects.
  ///
  /// Throws [ModelMissingException] when none of those turn up a file.
  static Future<String> locate(String assetPath) async {
    final String fileName = assetPath.split('/').last;

    final Directory documents = await getApplicationDocumentsDirectory();
    final File override = File('${documents.path}/models/$fileName');
    if (override.existsSync()) return override.path;

    final File inBundle = File(bundleAssetPath(assetPath));
    if (inBundle.existsSync()) return inBundle.path;

    return _extractFromAssets(assetPath, fileName);
  }

  /// Path of a Flutter asset inside the installed app bundle.
  ///
  /// On iOS `Platform.resolvedExecutable` is `…/Runner.app/Runner`, and the
  /// asset bundle sits at `Runner.app/Frameworks/App.framework/flutter_assets`.
  static String bundleAssetPath(String assetKey) {
    final String appDirectory = File(Platform.resolvedExecutable).parent.path;
    return '$appDirectory/Frameworks/App.framework/flutter_assets/$assetKey';
  }

  static Future<String> _extractFromAssets(
    String assetPath,
    String fileName,
  ) async {
    final Directory support = await getApplicationSupportDirectory();
    final Directory models = Directory('${support.path}/models');
    await models.create(recursive: true);

    final File destination = File('${models.path}/$fileName');
    if (destination.existsSync() && await destination.length() > 0) {
      return destination.path;
    }

    final ByteData data;
    try {
      data = await rootBundle.load(assetPath);
    } on FlutterError {
      throw ModelMissingException(fileName);
    }

    await destination.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    // The asset cache would otherwise hold the whole model in memory.
    rootBundle.evict(assetPath);

    return destination.path;
  }
}
