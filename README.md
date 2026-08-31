# 航海英语语音翻译（Marine Voice Translator）

纯离线的航海英语对讲 App，**仅面向 iPhone / iOS**，使用 Flutter 开发。面向夜间驾驶台场景：全程暗黑配色，翻译结果以 32pt 超大字号居中显示，底部两个巨大的独立按键分别对应「按住说英文」和「按住说中文」。

语音识别由本机 whisper.cpp 完成，翻译由 Qwen2.5-1.5B-Instruct（llama.cpp）完成。音频与文本都不离开设备，代码中没有任何网络调用。

## 当前进度

- **第一步 · 界面与录音**：夜间暗黑主界面、32pt 主显示区、两个巨型按住说话按键、16 kHz 单声道 PCM 采集。
- **第二步 · 离线识别**：接入 whisper.cpp（Metal 加速），松开按键后进入「正在识别中...」。
- **第三步 · 离线翻译**（当前）：识别完成后闪过原文，再进入「正在翻译...」，最终以 32pt 显示译文；底部 10pt 显示 `ASR: x.xs | LLM: y.ys`。

## 运行

需要 Flutter 3.29 以上（开发时使用 3.47.2 / Dart 3.13）、Xcode，以及一台 iOS 15.6 以上的 iPhone。

```bash
flutter pub get

# 模型不在仓库里，先下载（Whisper 约 547 MB + Qwen 约 1.1 GB）
curl -L -o assets/models/ggml-large-v3-turbo-q5_0.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin

curl -L -o assets/models/qwen2.5-1.5b-instruct-q4_k_m.gguf \
  https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf

cd ios && pod install && cd ..
flutter run -d <你的 iPhone>
```

模型缺失时 App 仍会启动，顶部状态条分别显示 ASR / LLM 是否就绪，按下按键会给出安装指引。详见 [`assets/models/README.md`](assets/models/README.md)。

校验：

```bash
flutter analyze
flutter test
```

桌面端可单独验证翻译提示词与术语表（需已下载 Qwen 模型）：

```bash
dart run tool/prompt_smoke_test.dart /path/to/qwen2.5-1.5b-instruct-q4_k_m.gguf
```

## 项目结构

```
lib/
├── main.dart                        # 应用入口 + 主界面（录音 → ASR → 翻译 状态机）
├── config/maritime_config.dart      # 热词、术语表、双模型路径
├── models/
│   ├── recognition_turn.dart        # 一次对讲的识别 + 翻译结果
│   ├── session_status.dart          # 待机 / 聆听 / 识别 / 翻译 / 完成 / 失败
│   └── speech_direction.dart        # 英/中两个方向的配色、文案与 whisper 语种
├── services/
│   ├── asr_service.dart             # whisper.cpp：模型定位、transcribe、热词注入
│   ├── llm_service.dart             # Qwen ChatML 翻译、术语强校、内存释放
│   ├── model_locator.dart           # 双模型共享的文件定位逻辑
│   ├── resident_model.dart          # 后台统一释放 ASR + LLM 权重
│   ├── translation_prompt.dart      # ChatML 提示词与输出端术语替换
│   └── pcm_recorder.dart            # 录音：AVAudioSession、16 kHz 单声道、WAV 落盘
├── theme/night_theme.dart
└── widgets/
    ├── bridge_status_bar.dart       # 顶部状态条（ASR / LLM / 麦克风）
    ├── push_to_talk_button.dart
    └── transcript_stage.dart        # 中央 32pt 译文舞台

local_plugins/
├── whisper_ggml/                    # whisper.cpp + Metal（fork）
└── llama_ggml/                      # llama.cpp + Metal（Qwen 翻译）
```

## 翻译流水线

一次按键的完整路径：

1. **聆听** — 16 kHz PCM 流式采集，电平驱动按键动画。
2. **识别** — 松开按键后 whisper 转写，显示「正在识别中...」与进度百分比。
3. **闪过原文** — 识别文本以 32pt 短暂显示约 0.7 秒。
4. **翻译** — Qwen 在 ChatML 提示词中注入 `MaritimeConfig.glossary`，显示「正在翻译...」。
5. **完成** — 32pt 显示译文，原文以 14pt 附在下方；底部 `ASR: x.xs | LLM: y.ys`。

术语表会**注入 system prompt**（防止左右舷颠倒）并在**输出端做强制替换**（兜底）。

## 配置

想调整专业词汇或换模型，改 `lib/config/maritime_config.dart`；词汇数据在 `lib/config/maritime_vocabulary.dart`：

- `hotwords` / `initialPrompt` — Whisper 热词（90 条，受 224 token 限制）
- `glossary` — 翻译术语对照表（110 条运行时注入）
- `vhfCorePhrases` / `vtsPhrases` — 566 条中英句对（参考库，默认不全部注入 LLM）
- `wordGlossary` — 359 个航海单词（完整词典）
- `modelAssetPath` / `llmModelAssetPath` — 双模型路径
- `useMetal` — 是否启用 Metal GPU

原始资料在 `tool/sources/`，重新整理词汇：

```bash
pip install olefile pdfplumber
python3 tool/extract_maritime_vocab.py
```

## 内存管理

Whisper turbo + Qwen 1.5B q4 同时常驻约 1.6 GB 权重。App 在退到后台时通过 `ResidentModels.releaseAll()` 释放两者；回到前台后下次按键会重新加载。

`ios/Runner/Runner.entitlements` 已申请 `com.apple.developer.kernel.increased-memory-limit`，争取更多前台内存额度（需在 Apple Developer 账号中启用对应 Capability）。

## Metal 硬件加速

两个插件均通过 `local_plugins/` 内的 fork 启用 ggml Metal 后端，详见各插件 README。`MaritimeConfig.useMetal` 是运行时开关，改成 `false` 可退回 CPU 后端做对比。

## 已知限制

- **双模型体积大。** IPA 约 1.6 GB；上架通常改为首次启动按需下载。
- **首次加载慢。** Metal 着色器按设备编译，每个进程一次；之后模型常驻直到退后台。
- **仅 iOS。** Linux 环境无法 `flutter build ios`；桌面端只能跑 `flutter test` 与 `tool/prompt_smoke_test.dart`。

## 平台配置

| 项目 | 位置 |
| --- | --- |
| 麦克风用途说明 | `ios/Runner/Info.plist` |
| 文件共享（放模型 / 取录音） | `Info.plist` |
| 提高内存上限 | `ios/Runner/Runner.entitlements` |
| 最低系统版本 | iOS 15.6 |

本项目只保留 `ios/` 一个平台目录。
