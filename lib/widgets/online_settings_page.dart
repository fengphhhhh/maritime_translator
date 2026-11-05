import 'package:flutter/material.dart';

import '../services/translation_settings.dart';

class OnlineSettingsPage extends StatefulWidget {
  const OnlineSettingsPage({
    super.key,
    required this.keyStore,
    required this.settings,
  });
  final ApiKeyStore keyStore;
  final TranslationSettings settings;
  @override
  State<OnlineSettingsPage> createState() => _OnlineSettingsPageState();
}

class _OnlineSettingsPageState extends State<OnlineSettingsPage> {
  final _key = TextEditingController();
  final _hotword = TextEditingController(
    text: OnlineVocabulary.defaultHotwordId,
  );
  final _glossary = TextEditingController(
    text: OnlineVocabulary.defaultGlossaryId,
  );
  bool _busy = false, _visible = false, _saved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkSaved();
  }

  Future<void> _checkSaved() async {
    try {
      final value = await widget.keyStore.read();
      if (mounted) setState(() => _saved = value?.isNotEmpty ?? false);
    } on Object {
      if (mounted) setState(() => _error = '无法读取密钥状态，请解锁手机后重试。');
    }
    try {
      final terms = await widget.settings.loadVocabulary();
      if (mounted) {
        _hotword.text = terms.hotwordTableId;
        _glossary.text = terms.glossaryTableId;
      }
    } on Object {
      if (mounted) setState(() => _error = '词表设置读取失败，请重新填写后保存。');
    }
  }

  @override
  void dispose() {
    _key.dispose();
    _hotword.dispose();
    _glossary.dispose();
    super.dispose();
  }

  Future<void> _save({bool delete = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (delete) {
        await widget.keyStore.delete();
      } else {
        final terms = OnlineVocabulary(
          hotwordTableId: _hotword.text.trim(),
          glossaryTableId: _glossary.text.trim(),
        );
        terms.validate();
        if (_key.text.trim().isNotEmpty) {
          await widget.keyStore.save(_key.text);
        } else if (!_saved) {
          throw const FormatException('Missing API key');
        }
        await widget.settings.saveVocabulary(terms);
      }
      _key.clear();
      if (mounted) Navigator.pop(context, true);
    } on FormatException {
      if (mounted) setState(() => _error = '请检查 API Key 和词表 ID 的格式。');
    } on Object {
      if (mounted) setState(() => _error = '密钥保存失败，请解锁手机后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('豆包在线设置')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '同声传译 2.0 · 语音到文本',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          const Text('在线模式下，松开按键后会把本段录音发送至豆包，返回原文和译文。需要网络，使用量按你的火山引擎账户计费。'),
          const SizedBox(height: 12),
          const Text(
            '请使用已开通豆包同声传译 2.0 服务的 API Key。密钥只保存在本机钥匙串；删除密钥可在此操作。离线模式不发送录音。',
          ),
          const SizedBox(height: 24),
          if (_saved) ...[
            const Text('已保存密钥。填写新值可以替换；留空不会显示或修改现有密钥。'),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _key,
            enabled: !_busy,
            obscureText: !_visible,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            textCapitalization: TextCapitalization.none,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: _saved ? '输入新密钥以替换' : '粘贴你的 API Key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _visible ? '隐藏密钥' : '显示密钥',
                onPressed: () => setState(() => _visible = !_visible),
                icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
              ),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _hotword,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: '热词表 ID（选填）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _glossary,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: '术语表 ID（选填）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          const Text('在线时优先使用已填写的词表；清空某项后，该项改用 App 内置的航海词汇提示。'),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : () => _save(),
            child: Text(_busy ? '正在保存…' : '保存设置'),
          ),
          if (_saved)
            TextButton(
              onPressed: _busy ? null : () => _save(delete: true),
              child: const Text('删除本机密钥'),
            ),
          const SizedBox(height: 20),
          const Text(
            '操作保持不变：选择在线 → 按住说英文或中文 → 松开后翻译。在线失败不会自动重新上传；可返回主页手动切换离线。',
          ),
        ],
      ),
    ),
  );
}
