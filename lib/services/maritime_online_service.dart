import 'dart:typed_data';

import 'ark_correction_service.dart';
import 'doubao_s2t_service.dart';
import 'translation_settings.dart';

/// Direct iPhone -> AST -> Ark. No application backend or local inference.
class MaritimeOnlineService extends DoubaoS2tService {
  MaritimeOnlineService({
    required this.keyStore,
    required this.settings,
    DoubaoS2tService? ast,
    ArkCorrectionService? ark,
  }) : _ast = ast ?? DoubaoS2tService(transcriptOnly: true),
       _ark = ark ?? ArkCorrectionService();

  final ApiKeyStore keyStore;
  final TranslationSettings settings;
  final DoubaoS2tService _ast;
  final ArkCorrectionService _ark;
  Object? _operation;

  @override
  Future<OnlineTranslation> translate({
    required Uint8List wav,
    required String apiKey,
    required bool englishSource,
    String hotwordTableId = '',
    String glossaryTableId = '',
    void Function(OnlineTranslation partial)? onUpdate,
  }) async {
    if (_operation != null) {
      throw const OnlineTranslationException('上一段在线翻译仍在处理中。');
    }
    final operation = Object();
    _operation = operation;
    void checkActive() {
      if (!identical(_operation, operation)) {
        throw const OnlineTranslationException('在线翻译已取消。');
      }
    }

    try {
      final arkKey = await keyStore.readArk();
      final model = await settings.loadArkModel();
      checkActive();
      if (arkKey == null || arkKey.trim().isEmpty) {
        throw const OnlineTranslationException('请先在在线设置中添加方舟 API Key。');
      }
      TranslationSettings.validateArkModel(model);
      final recognized = await _ast.translate(
        wav: wav,
        apiKey: apiKey,
        englishSource: englishSource,
        hotwordTableId: hotwordTableId,
        glossaryTableId: glossaryTableId,
        onUpdate: (partial) {
          if (identical(_operation, operation)) {
            onUpdate?.call(OnlineTranslation(partial.source, ''));
          }
        },
      );
      checkActive();
      onUpdate?.call(OnlineTranslation(recognized.source, ''));
      checkActive();
      final corrected = await _ark.correct(
        transcript: recognized.source,
        englishSource: englishSource,
        apiKey: arkKey,
        model: model,
      );
      checkActive();
      return corrected;
    } finally {
      if (identical(_operation, operation)) _operation = null;
    }
  }

  @override
  void cancel() {
    _operation = null;
    _ast.cancel();
    _ark.cancel();
  }
}
