# 航海英语语音翻译（Marine Voice Translator）

纯离线的航海英语对讲式翻译 App，基于 Flutter 跨平台开发。面向夜间驾驶台场景：全程暗黑配色，译文以 32pt 超大字号居中显示，底部两个巨大的独立按键分别对应「按住说英文」和「按住说中文」。

所有音频采集与处理都在本机完成，代码中没有任何网络调用。

## 已实现

- **夜间暗黑模式**：接近纯黑的深色底（`#05070C`）避免破坏夜视，英文侧用蓝色、中文侧用琥珀色区分方向，`themeMode` 固定为 `dark`，不跟随系统。
- **32pt 译文主显示区**：屏幕中央的译文是全屏最大的元素，可选中复制；下方以次要字号显示原文，并标注音频时长与音频规格。
- **两个巨型按住说话按键**：常规高度 168 逻辑像素，矮屏自动降到 128；始终左右并排，保证「左英右中」的肌肉记忆。按下时按键发光、显示分段电平条，另一个按键自动置灰。
- **16 kHz 单声道 PCM 录制**：通过 `record` 的 `startStream` 采集 `AudioEncoder.pcm16bits`、`sampleRate: 16000`、`numChannels: 1` 的裸 PCM 帧，直接就是 whisper.cpp / sherpa-onnx 等端上 ASR 引擎要求的输入格式，无需重采样。
- **完整状态覆盖**：待机、聆听中（计时 + 电平）、离线识别中、翻译完成、错误（含麦克风权限被拒）。
- **按压边界处理**：按住不足 400 ms 判为误触并提示；手势被系统取消或 App 退到后台时丢弃本次录音，不会翻译半截音频。

## 运行

需要 Flutter 3.27 或更高版本（开发时使用 3.47.2 / Dart 3.13）。

```bash
flutter pub get

flutter run                    # 连接的 Android / iOS 设备
flutter run -d chrome          # 浏览器（麦克风需要 https 或 localhost）
```

校验：

```bash
flutter analyze
flutter test
```

## 项目结构

```
lib/
├── main.dart                        # 应用入口 + 主界面 TranslatorHomePage（状态机在这里）
├── data/smcp_phrasebook.dart        # IMO 标准航海通信用语（SMCP）中英对照短语
├── models/
│   ├── session_status.dart          # 待机 / 聆听 / 解码 / 完成 / 失败
│   ├── speech_direction.dart        # 英译中、中译英，以及各自的配色与文案
│   └── translation_turn.dart        # 一次完整对讲的结果
├── services/
│   ├── pcm_recorder.dart            # record 封装：16 kHz 单声道 PCM 采集、电平计算、WAV 导出
│   └── translation_engine.dart      # 翻译引擎接口 + 占位实现
├── theme/night_theme.dart           # 夜间配色与 ThemeData
└── widgets/
    ├── bridge_status_bar.dart       # 顶部状态条（离线标识、麦克风权限）
    ├── push_to_talk_button.dart     # 巨型按住说话按键
    └── translation_stage.dart       # 中央 32pt 译文舞台
```

## 音频管线

`PcmRecorder` 用流式而非文件方式录音，因为离线翻译需要的是内存里的缓冲区而不是磁盘文件：

- 格式固定为 16 kHz / 单声道 / 16-bit 小端 PCM，常量集中在 `PcmFormat`。
- 每个数据块约 128 ms（`streamBufferSize: 4096`），用于驱动界面上的实时电平条；电平由 PCM 采样的 RMS 换算成 dBFS，以 -55 dBFS 为底噪基准归一化。
- Android 使用 `AndroidAudioSource.voiceRecognition`，让系统对机舱与驾驶台噪声应用语音前端处理。
- 松开按键后不会立即取消订阅，而是等待流的 `done` 事件，确保拿到录音末尾的数据。
- 每段录音会额外镜像一份 `.pcm` 文件到应用文档目录的 `captures/`（Web 平台跳过），方便排查识别效果；`PcmClip.toWav()` 可以给这段裸数据补上 RIFF 头，用任意播放器试听。

## 接入真实的离线翻译模型

当前 `DemoPhrasebookEngine` 是**占位实现**：它不分析音频内容，只是按顺序取用内置的 SMCP 短语，并按音频长度模拟推理耗时，目的是让整套界面和录音链路可以完整跑通。

替换方式是实现 `TranslationEngine` 接口，然后在 `_TranslatorHomePageState` 中换掉 `_engine` 的赋值：

```dart
abstract interface class TranslationEngine {
  String get displayName;
  Future<TranslationTurn> process(PcmClip clip, {required SpeechDirection direction});
}
```

`clip.bytes` 就是可以直接喂给模型的 16 kHz 单声道 PCM。推荐的端上组合是 sherpa-onnx 或 whisper.cpp 做语音识别，再接一个量化过的 NMT 模型做翻译；模型文件随包分发或首次启动时导入即可。

## 平台权限

| 平台 | 配置 |
| --- | --- |
| Android | `AndroidManifest.xml` 中的 `RECORD_AUDIO` 权限与 `android.hardware.microphone` 特性；`record_android` 要求 minSdk 23 |
| iOS | `Info.plist` 中的 `NSMicrophoneUsageDescription` |
| Web | 浏览器在 https 或 localhost 下弹出麦克风授权 |

运行时的权限申请由 `record` 的 `hasPermission()` 处理，顶部状态条会显示当前授权状态，未授权时点击即可发起申请。
