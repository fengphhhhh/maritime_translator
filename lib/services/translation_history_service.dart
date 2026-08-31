import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/recognition_turn.dart';
import '../models/translation_history_entry.dart';

/// Persists successful translations locally via [SharedPreferences].
class TranslationHistoryService {
  TranslationHistoryService({this._preferences});

  static const _storageKey = 'translation_history_v1';
  static const _maxEntries = 200;

  SharedPreferences? _preferences;

  Future<SharedPreferences> _prefs() async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  Future<List<TranslationHistoryEntry>> loadAll() async {
    final raw = (await _prefs()).getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];

    final decoded = jsonDecode(raw);
    if (decoded is! List<Object?>) return const [];

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(TranslationHistoryEntry.fromJson)
        .toList(growable: false);
  }

  Future<void> appendFromTurn(RecognitionTurn turn) async {
    if (!turn.hasTranslation || turn.sourceText.isEmpty) return;

    final entry = TranslationHistoryEntry(
      id: turn.createdAt.microsecondsSinceEpoch.toString(),
      sourceText: turn.sourceText,
      translationText: turn.translation,
      direction: turn.direction,
      timestamp: TranslationHistoryEntry.formatTimestamp(turn.createdAt),
    );

    final existing = await loadAll();
    final updated = <TranslationHistoryEntry>[entry, ...existing];
    if (updated.length > _maxEntries) {
      updated.removeRange(_maxEntries, updated.length);
    }

    await _save(updated);
  }

  Future<void> clearAll() async {
    await (await _prefs()).remove(_storageKey);
  }

  Future<void> _save(List<TranslationHistoryEntry> entries) async {
    final encoded = jsonEncode(entries.map((entry) => entry.toJson()).toList());
    await (await _prefs()).setString(_storageKey, encoded);
  }
}
