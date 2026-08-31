# 航海英语语音翻译（Marine Voice Translator）

纯离线的航海英语对讲 App，**仅面向 iPhone / iOS**，使用 Flutter 开发。面向夜间驾驶台场景：全程暗黑配色，识别结果以 32pt 超大字号居中显示，底部两个巨大的独立按键分别对应「按住说英文」和「按住说中文」。

语音识别由本机 whisper.cpp 完成，音频与文本都不离开设备，代码中没有任何网络调用。

## 当前进度

- **第一步 · 界面与录音**：夜间暗黑主界面、32pt 主显示区、两个巨型按住说话按键、16 kHz 单声道 PCM 采集。
- **第二步 · 离线识别**（当前）：接入 whisper.cpp，松开按键后进入「正在识别中...」，识别文本呈现在 32pt 区域。
- **下一步 · 离线翻译**：识别结果之上再接一层端上翻译。目前 32pt 区域显示的是**识别原文**，尚未翻译。

## 运行

需要 Flutter 3.29 以上（开发时使用 3.47.2 / Dart 3.13）、Xcode，以及一台 iOS 15.6 以上的 iPhone。

```bash
flutter pub get

# 模型不在仓库里，先下载（约 547 MB）
curl -L -o assets/models/ggml-large-v3-turbo-q5_0.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin

cd ios && pod install && cd ..
flutter run -d <你的 iPhone>
```

模型缺失时 App 仍会启动，顶部状态条显示「模型缺失」，按下按键会给出安装指引。详见 [`assets/models/README.md`](assets/models/README.md)。

校验：

```bash
flutter analyze
flutter test
```

## 项目结构

```
lib/
├── main.dart                        # 应用入口 + 主界面 TranslatorHomePage（状态机在这里）
├── config/maritime_config.dart      # 航海热词与模型路径（唯一需要改的配置文件）
├── models/
│   ├── recognition_turn.dart        # 一次对讲的识别结果
│   ├── session_status.dart          # 待机 / 聆听 / 识别 / 完成 / 失败
│   └── speech_direction.dart        # 英/中两个方向的配色、文案与 whisper 语种
├── services/
│   ├── asr_service.dart             # whisper.cpp 胶水层：模型定位、transcribe、热词注入
│   └── pcm_recorder.dart            # 录音：AVAudioSession、16 kHz 单声道采集、WAV 落盘
├── theme/night_theme.dart           # 夜间配色与 ThemeData
└── widgets/
    ├── bridge_status_bar.dart       # 顶部状态条（离线、模型、麦克风）
    ├── push_to_talk_button.dart     # 巨型按住说话按键
    └── transcript_stage.dart        # 中央 32pt 结果舞台
```

## 配置：热词与模型

想调整专业词汇或换模型，只改 `lib/config/maritime_config.dart` 一个文件：

```dart
abstract final class MaritimeConfig {
  static const String modelAssetPath =
      'assets/models/ggml-large-v3-turbo-q5_0.bin';

  static const List<String> hotwords = [
    'VTS', 'CPA', 'TCPA', 'UKC', 'ECDIS', 'AIO', 'Port Bow', 'Starboard',
    'Underway', 'Draught', 'Anchor', 'Pilot', 'Gangway', 'Fairway',
    'Master', 'Chief Officer', 'Second Mate', 'Dredger',
  ];

  static const int decoderThreads = 4;
}
```

`hotwords` 会拼成 `initial_prompt` 传给 whisper.cpp 的 `whisper_full_params.initial_prompt`，让解码偏向这些词——没有它，`CPA` 常被听成 "see PA"、`Draught` 被写成 "draft"。两点注意：

- prompt 有 224 token 的预算，超出部分会被静默丢弃，所以词表要精简。
- whisper 会**模仿 prompt 的书写风格**。`promptPreamble` 保持了正常的大小写和标点，输出才不会变成一长串无标点文本。

`pubspec.yaml` 声明的是整个 `assets/models/` 目录，所以换模型时只需要放入新文件并改 `modelAssetPath`，不用动构建配置。

## 音频管线

`PcmRecorder` 用 `record` 的流式接口而不是文件接口录音：

- 格式固定 16 kHz / 单声道 / 16-bit 小端 PCM，常量集中在 `PcmFormat`，正是 whisper 要求的输入。
- 每块约 128 ms（`streamBufferSize: 4096`），实时算 RMS 驱动按键上的电平条。
- **WAV 头由本类自己写**（`PcmClip.toWav()`），而不是交给编码器，这样头里声明的采样率、声道数、位深一定是 whisper 想要的那组值。
- 松开按键后不会立即取消订阅，而是等流的 `done` 事件，否则会丢掉录音末尾。
- 成品写入 `Documents/recordings/<时间戳>.wav`，只保留最近 20 个文件。`Info.plist` 打开了 `UIFileSharingEnabled`，可以用「文件」App 直接把录音拷出来排查识别效果。

### AVAudioSession

`PcmRecorder.configureAudioSession()` 在启动时把会话类别钉成 `playAndRecord`，选项为 `defaultToSpeaker + allowBluetooth + duckOthers`，让配置留在应用里而不是依赖插件默认值。另外 `allowHapticsAndSystemSoundsDuringRecording` 打开，来电振铃不会中断录音，只有真正接听才会。

## Whisper 胶水层

`AsrService.transcribe(String audioPath)` 是唯一的对外入口，返回识别文本。内部要点：

| 参数 | 取值 | 原因 |
| --- | --- | --- |
| `initialPrompt` | `MaritimeConfig.initialPrompt` | 航海热词注入 |
| `noContext` | `true` | 每次按键是独立语句，跨段上下文是短音频幻觉重复的主要来源 |
| `suppressNonSpeechTokens` | `true` | 松手慢半拍时不会写出 `[BLANK_AUDIO]` |
| `keepModelLoaded` | `true` | q5_0 turbo 模型加载要好几秒，常驻内存后只有第一次按键付这个代价 |
| `isTranslate` | `false` | 这一步只做识别 |

模型按以下顺序定位：

1. `Documents/models/<文件名>` —— 通过「文件」App 放进去的模型，可以不重编就换成微调版本。
2. App Bundle 内的 `flutter_assets/assets/models/<文件名>` —— **原地读取，不复制**。几百兆的模型多存一份既费磁盘又费内存。
3. 从 Flutter asset bundle 解压到 `Application Support/models/`，作为路径推断失效时的兜底。

App 退到后台时会调用 `AsrService.release()` 释放常驻内存中的模型——iOS 会杀掉在后台占着几 GB 内存的应用。

## Metal 硬件加速

pub.dev 上的 `whisper_ggml` 在 iOS 上只编译 CPU + Accelerate 后端，源码树里连 Metal 后端的实现文件都没有，large-v3-turbo 因此跑不进几秒的业务预算。`local_plugins/whisper_ggml/` 是它的分支，补齐了 ggml 的 Metal 后端；`pubspec.yaml` 通过 `path:` 指向这份分支。

改动内容见 [`local_plugins/whisper_ggml/README.md`](local_plugins/whisper_ggml/README.md) 顶部的分支说明。

`MaritimeConfig.useMetal` 是运行时开关，会作为 `whisper_context_params.use_gpu` 传到原生层。改成 `false` 即可退回 CPU 后端，不需要重新编译原生代码——某台设备在 Metal 下表现异常时可以这样先顶住。

## 已知限制

- **large-v3-turbo 仍然不轻。** 识别耗时会显示在结果下方；真机实测偏慢的话，把 `modelAssetPath` 换成 `ggml-medium-q5_0.bin` 或 `ggml-small-q5_1.bin` 即可。
- **首次加载会多花几秒。** Metal 着色器是在运行时按设备能力编译的（见分支说明），每个进程一次。之后 `keepModelLoaded` 会让上下文常驻，按键到出字的延迟不含这部分。
- **多带了一个 ffmpeg 依赖。** `whisper_ggml` 会先把输入音频过一遍 ffmpeg，因此传递依赖了 `ffmpeg_kit_flutter_new_min`，会让 IPA 变大。我们的音频本来就是目标格式，所以那次转换只是拷贝，产生的 `<路径>.wav.wav` 中间文件在转写后会被删掉。
- **模型体积。** 547 MB 打进包里会让 IPA 很大，且 App Store 有下载体积限制。真要上架，一般改成首次启动按需下载到 `Documents/models/`。

## 平台配置

| 项目 | 位置 |
| --- | --- |
| 麦克风用途说明 | `ios/Runner/Info.plist` 的 `NSMicrophoneUsageDescription` |
| 文件共享（放模型 / 取录音） | `Info.plist` 的 `UIFileSharingEnabled`、`LSSupportsOpeningDocumentsInPlace` |
| 最低系统版本 | iOS 15.6（`whisper_ggml` 的 pod 要求），已同步到 `Podfile` 与 Xcode 工程 |

本项目只保留 `ios/` 一个平台目录，Android 与 Web 已移除。
