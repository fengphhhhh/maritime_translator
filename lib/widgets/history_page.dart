import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/translation_history_entry.dart';
import '../services/translation_history_service.dart';
import '../theme/night_theme.dart';
import 'marine_card.dart';

/// Scrollable log of past bridge translations.
class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    this.historyService,
  });

  final TranslationHistoryService? historyService;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late final TranslationHistoryService _service =
      widget.historyService ?? TranslationHistoryService();

  List<TranslationHistoryEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final entries = await _service.loadAll();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NightPalette.surfaceRaised,
        title: const Text('清空历史记录'),
        content: const Text('将删除全部本地对讲历史，此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: NightPalette.danger),
            child: const Text('清空'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _service.clearAll();
    await _reload();
  }

  Future<void> _copyEntry(TranslationHistoryEntry entry) async {
    final buffer = StringBuffer()
      ..writeln('[${entry.directionLabel}] ${entry.timestamp}')
      ..writeln('原文：${entry.sourceText}')
      ..writeln('译文：${entry.translationText}');
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: NightPalette.background,
        foregroundColor: NightPalette.textPrimary,
        elevation: 0,
        title: const Text(
          '对讲历史',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.6),
        ),
        actions: [
          if (_entries.isNotEmpty)
            TextButton(
              onPressed: () => unawaited(_clearAll()),
              child: const Text('清空'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _entries.isEmpty
          ? const _EmptyHistory()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              itemCount: _entries.length,
              separatorBuilder: (context, index) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final entry = _entries[index];
                return _HistoryTile(
                  entry: entry,
                  onCopy: () => unawaited(_copyEntry(entry)),
                );
              },
            ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_rounded,
              size: 56,
              color: NightPalette.textMuted.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 16),
            const Text(
              '暂无历史记录',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: NightPalette.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '完成一次翻译后会自动保存在本机。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: NightPalette.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry, required this.onCopy});

  final TranslationHistoryEntry entry;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final accent = entry.direction.accent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onCopy,
        borderRadius: BorderRadius.circular(22),
        child: MarineCard(
          accent: accent,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _DirectionChip(label: entry.directionLabel, accent: accent),
                  const Spacer(),
                  Text(
                    entry.timestamp,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: NightPalette.textMuted,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                entry.sourceText,
                style: TextStyle(
                  fontSize: 20,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                  color: accent.withValues(alpha: 0.92),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                entry.translationText,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                  color: NightPalette.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '点击复制',
                  style: TextStyle(
                    fontSize: 12,
                    color: NightPalette.textMuted.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectionChip extends StatelessWidget {
  const _DirectionChip({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.38)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: accent,
        ),
      ),
    );
  }
}
