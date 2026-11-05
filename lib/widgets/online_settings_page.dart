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
  final _arkKey = TextEditingController();
  final _model = TextEditingController(
    text: TranslationSettings.defaultArkModel,
  );
  final _hotword = TextEditingController(
    text: OnlineVocabulary.defaultHotwordId,
  );
  final _glossary = TextEditingController(
    text: OnlineVocabulary.defaultGlossaryId,
  );
  bool _busy = false, _visible = false, _saved = false, _arkSaved = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkSaved();
  }

  Future<void> _checkSaved() async {
    try {
      final value = await widget.keyStore.read();
      final ark = await widget.keyStore.readArk();
      if (mounted) {
        setState(() {
          _saved = value?.isNotEmpty ?? false;
          _arkSaved = ark?.isNotEmpty ?? false;
        });
      }
    } on Object {
      if (mounted) setState(() => _error = '无法读取密钥状态，请解锁手机后重试。');
    }
    try {
      final terms = await widget.settings.loadVocabulary();
      final model = await widget.settings.loadArkModel();
      if (mounted) {
        _hotword.text = terms.hotwordTableId;
        _glossary.text = terms.glossaryTableId;
        _model.text = model;
      }
    } on Object {
      if (mounted) setState(() => _error = '词表设置读取失败，请重新填写后保存。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _key.dispose();
    _arkKey.dispose();
    _model.dispose();
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
        await widget.keyStore.deleteArk();
      } else {
        final terms = OnlineVocabulary(
          hotwordTableId: _hotword.text.trim(),
          glossaryTableId: _glossary.text.trim(),
        );
        terms.validate();
        TranslationSettings.validateArkModel(_model.text.trim());
        if ((_key.text.trim().isEmpty && !_saved) ||
            (_arkKey.text.trim().isEmpty && !_arkSaved)) {
          throw const FormatException('Both credentials required');
        }
        if (_key.text.trim().isNotEmpty) {
          await widget.keyStore.save(_key.text);
        }
        if (_arkKey.text.trim().isNotEmpty) {
          await widget.keyStore.saveArk(_arkKey.text);
        }
        await widget.settings.saveVocabulary(terms);
        await widget.settings.saveArkModel(_model.text);
      }
      _key.clear();
      _arkKey.clear();
      if (mounted) Navigator.pop(context, true);
    } on FormatException {
      if (mounted) setState(() => _error = '请填写两个服务的密钥，并检查模型 ID 和词表 ID。');
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
            'AST 识别 + 方舟海事校正',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          const Text(
            '松开按键后，App 直接把录音发送至 AST，再把识别文本交给 Doubao-Seed-2.1-pro 校正并翻译。无需后端；两个服务分别按你的账户计费。',
          ),
          const SizedBox(height: 12),
          const Text(
            'AST 和方舟使用各自已开通服务的 API Key，通常不是同一个密钥。密钥只保存在本机钥匙串，不随安装包分发。离线模式不发送录音或文本。',
          ),
          const SizedBox(height: 24),
          if (_saved || _arkSaved) ...[
            Text(
              'AST 密钥${_saved ? "已保存" : "未设置"}；方舟密钥${_arkSaved ? "已保存" : "未设置"}。已保存的密钥留空可保留，填写新值可替换。',
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _key,
            enabled: !_busy && !_loading,
            obscureText: !_visible,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            textCapitalization: TextCapitalization.none,
            decoration: InputDecoration(
              labelText: 'AST API Key',
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
            controller: _arkKey,
            enabled: !_busy && !_loading,
            obscureText: !_visible,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            decoration: InputDecoration(
              labelText: '方舟 API Key',
              hintText: _arkSaved ? '留空保留已保存密钥' : '粘贴方舟 API Key',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _model,
            enabled: !_busy && !_loading,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: '方舟模型 ID / 接入点 ID',
              helperText: '填写你已开通的 Seed-2.1-pro 模型 ID 或 ep- 接入点',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _hotword,
            enabled: !_busy && !_loading,
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
            enabled: !_busy && !_loading,
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
            onPressed: _busy || _loading ? null : () => _save(),
            child: Text(_busy ? '正在保存…' : '保存设置'),
          ),
          if (_saved || _arkSaved)
            TextButton(
              onPressed: _busy || _loading ? null : () => _save(delete: true),
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
