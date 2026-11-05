import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/translation_mode.dart';

/// Credentials belong to the iOS Keychain, never preferences or history.
class ApiKeyStore {
  static const channel = MethodChannel('marine_voice_translator/api_key');

  Future<String?> read() => channel.invokeMethod<String>('read');

  Future<void> save(String key) async {
    final value = key.trim();
    if (value.isEmpty ||
        value.length > 4096 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      throw const FormatException('请输入有效的 API Key。');
    }
    await channel.invokeMethod<void>('save', value);
  }

  Future<void> delete() => channel.invokeMethod<void>('delete');
}

class TranslationSettings {
  static const _modeKey = 'translation_mode_v1';

  Future<OnlineVocabulary> loadVocabulary() async {
    final prefs = await SharedPreferences.getInstance();
    return OnlineVocabulary(
      hotwordTableId:
          prefs.getString('doubao_hotword_table_id') ??
          OnlineVocabulary.defaultHotwordId,
      glossaryTableId:
          prefs.getString('doubao_glossary_table_id') ??
          OnlineVocabulary.defaultGlossaryId,
    );
  }

  Future<void> saveVocabulary(OnlineVocabulary value) async {
    value.validate();
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
          'doubao_hotword_table_id',
          value.hotwordTableId.trim(),
        ) ||
        !await prefs.setString(
          'doubao_glossary_table_id',
          value.glossaryTableId.trim(),
        )) {
      throw StateError('无法保存词表设置');
    }
  }

  Future<TranslationMode> loadMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_modeKey) == 'online'
        ? TranslationMode.online
        : TranslationMode.offline;
  }

  Future<void> saveMode(TranslationMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_modeKey, mode.name)) {
      throw StateError('无法保存模式设置');
    }
  }
}

class OnlineVocabulary {
  const OnlineVocabulary({
    this.hotwordTableId = defaultHotwordId,
    this.glossaryTableId = defaultGlossaryId,
  });
  static const defaultHotwordId = 'ddbca3f0-6643-488a-ab22-aa9132d28f0f';
  static const defaultGlossaryId = '718364fe-dcd3-4dd5-bf57-b1dfeab7826a';
  final String hotwordTableId, glossaryTableId;
  void validate() {
    final pattern = RegExp(r'^[a-zA-Z0-9_-]{1,128}$');
    for (final id in [hotwordTableId.trim(), glossaryTableId.trim()]) {
      if (id.isNotEmpty && !pattern.hasMatch(id)) {
        throw const FormatException('词表 ID 格式错误。');
      }
    }
  }
}
