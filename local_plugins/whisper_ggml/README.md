> ## 本分支说明：开启 Metal
>
> 这是 `whisper_ggml` 2.6.0 的分支，用于让 whisper.cpp 跑在 iPhone GPU 上。上游包在 iOS 上只编译 CPU + Accelerate 后端，`ggml/src/` 下面没有任何 Metal 后端的实现文件——只有一个 `ggml-metal.h` 头。以下是相对上游的全部改动。
>
> ### 1. 植入 Metal 后端源码
>
> 从 whisper.cpp v1.9.1（与本包内已有的 ggml 树同版本）取来 `ggml/src/ggml-metal/`。这一代 ggml 已经把 Metal 后端拆开了，**没有单个 `ggml-metal.m`**，实际编译单元是六个：
>
> ```
> ggml-metal.cpp          ggml-metal-device.m
> ggml-metal-common.cpp   ggml-metal-context.m
> ggml-metal-device.cpp   ggml-metal-ops.cpp
> ```
>
> 一处可移植性补丁：`ggml-metal.cpp` 用了 `std::unique_ptr` 却没有 `#include <memory>`。libc++ 会传递包含所以 iOS 上不报错，补上是为了让这份源码能被非 Apple 工具链做静态检查。
>
> ### 2. 着色器嵌入二进制，而不是打进 bundle
>
> 这一步决定了运行时会不会因为找不到 shader 而崩。`ggml-metal-device.m` 有三条加载路径：嵌入的源码、bundle 里的 `default.metallib`、bundle 里的 `.metal` 源码。**本分支走第一条**，理由是后两条都得在构建期把功能宏定死：
>
> ggml 是在运行时探测设备的 bf16 / tensor 能力，再把 `GGML_METAL_HAS_BF16` 之类的宏传给 `newLibraryWithSource:` 去编译着色器的。预编译的 metallib 只能赌一个固定配置，一旦和设备不符，缺失的 kernel 会让 `newFunctionWithName` 返回 nil。嵌入方案同时也不再需要 `[NSBundle bundleForClass:]` 去找资源。
>
> 代价是每个进程首次初始化后端时要编译一次着色器（几秒，之后由系统着色器缓存兜底）。这发生在模型加载阶段，不计入单次识别延迟。
>
> 具体做法：`tool/gen_metal_embed.sh` 复刻上游 CMake 的两步 sed，把 `ggml-common.h` 和 `ggml-metal-impl.h` 内联进 `ggml-metal.metal`，产出自包含的 `ggml-metal-embed.metal`（约 595 KB，已提交）。`ggml-metal-embed.S` 用 `.incbin` 把它塞进 `__DATA,__ggml_metallib` 段，导出 `_ggml_metallib_start` / `_ggml_metallib_end` 两个符号。升级 ggml 后重跑该脚本即可。
>
> ### 3. podspec 改动
>
> | 项 | 改动 | 作用 |
> | --- | --- | --- |
> | `GCC_PREPROCESSOR_DEFINITIONS` | 加 `GGML_USE_METAL=1` | `ggml-backend-reg.cpp` 里已有的 `#ifdef` 会据此注册 `ggml_backend_metal_reg()` |
> | `GCC_PREPROCESSOR_DEFINITIONS` | 加 `GGML_METAL_EMBED_LIBRARY=1` | 走嵌入着色器那条加载路径 |
> | `source_files` | 通配加 `m`、`S` | 纳入两个 Metal 的 `.m` 与嵌入用的 `.S`；**`.metal` 故意不加**，它是 `.incbin` 的数据而非编译单元 |
> | `preserve_paths` | 新增，覆盖 `*.metal` | 确保着色器文件随 pod 保留 |
> | `OTHER_CFLAGS` | 加 `-I.../ggml-metal` | `.incbin` 用的是不带目录的文件名，汇编器需要这个搜索路径。**缺了它会构建失败** |
> | `HEADER_SEARCH_PATHS` | 加 `ggml/src/ggml-metal` | Metal 源码之间互相引用的头 |
> | `frameworks` | 加 `Foundation`、`Metal`、`MetalKit` | 链接 Metal |
> | `requires_arc` | 设为 `false` | 两个 Metal 的 `.m` 是手动引用计数写的；本 pod 没有其他 Objective-C |
>
> 若某个 Xcode 版本没把 `OTHER_CFLAGS` 传给汇编器，`.incbin` 会报 `Could not find incbin file`。退路是在 `GCC_PREPROCESSOR_DEFINITIONS` 里定义 `GGML_METAL_EMBED_PATH` 为该文件的绝对路径，`ggml-metal-embed.S` 支持这个宏覆盖。
>
> ### 4. FFI 胶水层不再写死 CPU
>
> `whisper_flutter_plus.cpp` 里有两处 `cparams.use_gpu = false; // CPU-only build`（一次性转写与实时流各一处），只加编译宏是不够的。现改为由请求决定，并新增 Dart 侧字段：
>
> `TranscribeRequest.useGpu`（默认 `true`）→ JSON 键 `use_gpu` → `whisper_context_params.use_gpu`。
>
> 请求可以关掉 GPU，但在没有编译进 GPU 后端的构建上无法打开。`use_gpu` 在模型加载时就固定下来，因此常驻模型的缓存键也一并带上了它——否则切换开关会复用到后端不匹配的上下文。
>
> ### 5. 其他
>
> 上游的 `android/` `macos/` `windows/` `linux/` 目录连同各自的 whisper.cpp 副本一并删除，Metal 后端只需在一处维护。`pubspec.yaml` 的插件平台声明也相应收窄到 `ios`。

<div align="center">

# Whisper GGML

_On-device speech-to-text for Flutter, powered by [whisper.cpp](https://github.com/ggml-org/whisper.cpp) v1.9.1._

<p align="center">
  <a href="https://pub.dev/packages/whisper_ggml">
     <img src="https://img.shields.io/pub/v/whisper_ggml?logo=dart&color=blue" alt="pub">
  </a>
  <a href="https://github.com/ggml-org/whisper.cpp">
     <img src="https://img.shields.io/badge/whisper.cpp-v1.9.1-green" alt="whisper.cpp">
  </a>
  <a href="https://buymeacoffee.com/sk3llo" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/default-orange.png" alt="Buy Me A Coffee" height="21" width="114"></a>
</p>

Transcribe audio files or **transcribe live while the user speaks** — fully
on-device, no server, no API keys.

</div>

## Highlights

- 🎙 **Live transcription** — partial transcripts stream in while recording,
  refined as more audio arrives. The model loads once per session and an
  adaptive energy gate keeps silence from producing hallucinated text.
- 📄 **File transcription** — one call to transcribe a recording.
- 📦 **Offline-first** — models download once and are cached, or ship them
  in your app's assets for fully offline use (see the example app).
- 🌍 **99 languages** — pick one (`'en'`, `'fr'`, `'de'`, …) or use
  `'auto'` to detect.
- 🎛 **Decoding controls** — vocabulary biasing, context conditioning, and
  non-speech token suppression exposed from whisper.cpp.
- ⚡ **Fast** — whisper.cpp v1.9.1 with Accelerate on Apple platforms;
  an 11-second clip transcribes in ~0.4 s with the `base` model on an
  Apple Silicon Mac.

## Supported platforms

| Platform | Minimum version |
|----------|-----------------|
| Android  | API 21          |
| iOS      | 15.6            |
| macOS    | 10.15           |
| Windows  | 10 (x64)        |
| Linux    | x64             |

## Installation

```yaml
dependencies:
  whisper_ggml: ^2.6.0
```

Requires Dart 3.7+ (Flutter 3.29+).

## Quick start

```dart
import 'package:whisper_ggml/whisper_ggml.dart';

final controller = WhisperController();

final result = await controller.transcribe(
  model: WhisperModel.tiny,
  audioPath: '/path/to/audio.wav',
  lang: 'en',
);

print(result?.transcription.text);
```

Pass `onProgress: (percent) => ...` to receive transcription progress
as a 0–100 percentage (coarse steps) while inference runs.

Pass `withSegments: true` to also get per-segment timestamps in
`result.transcription.segments` (each segment has `fromTs`/`toTs`
`Duration`s and its `text`); add `splitOnWord: true` for one segment
per word instead of per phrase.

### Speaker-turn detection (diarization)

With the tinydiarize model (`WhisperModel.smallEnTdrz`, English only),
`diarize: true` marks the segments after which the speaker changes:

```dart
final result = await controller.transcribe(
  model: WhisperModel.smallEnTdrz,
  audioPath: '/path/to/audio.wav',
  lang: 'en',
  diarize: true,
  withSegments: true,
);

for (final segment in result?.transcription.segments ?? []) {
  print('${segment.text}${segment.speakerTurnNext ? ' [speaker turn]' : ''}');
}
```

This detects turn boundaries; it does not label or count speakers. With
regular models `diarize` has no effect.

The model is downloaded automatically on first use. Non-WAV input is
converted with the bundled FFmpeg — except on Windows and Linux, where
FFmpeg is not bundled: an `ffmpeg` executable on `PATH` is used when
present (on Linux, `apt install ffmpeg` or equivalent), otherwise the
input must already be a 16 kHz mono WAV (the format the `record` package
produces with `AudioEncoder.wav`, `sampleRate: 16000`, `numChannels: 1`).

## Live (streaming) transcription

`transcribeLive` accepts any stream of **16 kHz mono little-endian PCM16**
audio and emits progressively refined transcripts while the audio flows.
With the [`record`](https://pub.dev/packages/record) package:

```dart
final pcmStream = await recorder.startStream(const RecordConfig(
  encoder: AudioEncoder.pcm16bits,
  sampleRate: 16000,
  numChannels: 1,
));

final session = await controller.transcribeLive(
  model: WhisperModel.base,
  pcm16Stream: pcmStream,
  lang: 'en',
);

session.partials.listen((text) {
  print(text); // full transcript so far, not a delta
});

// Later — stop recording, finalize, and free the model:
await recorder.stop();
final finalText = await session.stop();
```

Good to know:

- The model stays loaded for the whole session; inference runs on a
  background isolate and never blocks the UI.
- An **adaptive energy gate** keeps silence away from the decoder, which
  otherwise hallucinates on silent audio. For unusually loud rooms or quiet
  speakers, tune `gateNoiseFloorCap`, `gateVoiceRatio`, and `gateRmsMin`.
- Only one live session can run at a time.
- Real non-speech sounds (knocks, clicks) may transcribe as bracketed
  annotations like `[door slams]`.
- **Bring your own model:** pass `modelPath:` instead of `model:` to run
  the session against any local ggml model file. For full manual control,
  `startWhisperLiveSession(modelPath: ...)` is exported too — no audio
  stream wiring, you call `session.feed(pcm16Bytes)` yourself.
- **Session-per-utterance?** Pass `keepModelLoaded: true` and the model is
  parked in native memory when the session stops, so the next session (or
  one-shot `transcribe`) with the same model starts without the
  multi-second load. See "Keeping the model loaded between transcriptions"
  below — the same cache, memory trade-off, and `releaseModel()` apply.

## Models

| Model | Multilingual | English-only |
|-------|--------------|--------------|
| tiny   | `WhisperModel.tiny`   | `WhisperModel.tinyEn`   |
| base   | `WhisperModel.base`   | `WhisperModel.baseEn`   |
| small  | `WhisperModel.small`  | `WhisperModel.smallEn`  |
| medium | `WhisperModel.medium` | `WhisperModel.mediumEn` |
| large-v3 | `WhisperModel.large` | —                      |

Smaller models are faster; larger models are more accurate. `tiny` and
`base` are good defaults for live transcription; `small` is a strong
accuracy/speed balance for file transcription on modern phones.

## Decoding options

Available on both `transcribe` and `transcribeLive`:

| Option | Default | What it does |
|--------|---------|--------------|
| `initialPrompt` | `null` | Biases decoding toward the vocabulary, names, and punctuation it contains — useful for domain-specific terms that otherwise get misrecognised. Decoding also mimics the prompt's *style*: an unpunctuated prompt tends to produce unpunctuated output. |
| `noContext` | `false` | Stops whisper from conditioning on prior-segment transcripts (like Python whisper's `condition_on_previous_text=False`). Helps against hallucinated repetition on short, independent utterances. |
| `suppressNonSpeechTokens` | `false` | Suppresses bracketed annotations such as `[BLANK_AUDIO]` or `[music]`. Side effect: real sounds may decode as plausible-looking words instead, which is why the example keeps it off. |

## Keeping the model loaded between transcriptions

By default every `transcribe` call loads the model from disk (seconds for
the small models and up) and frees it when the request completes. For
push-to-talk dictation, voice notes, and other short repeated requests
against the same model, that load dominates the per-utterance latency.
Pass `keepModelLoaded: true` to park the loaded model in native memory
instead — the next transcription with the same model skips the load:

```dart
final result = await controller.transcribe(
  model: WhisperModel.base,
  audioPath: audioPath,
  keepModelLoaded: true, // model stays resident for the next request
);

// When dictation is over, free the parked model:
await controller.releaseModel();
```

Good to know:

- A reused model transcribes **exactly like a freshly loaded one** — no
  text or decoder state carries over between requests.
- The parked model keeps its weights in RAM (from ~100 MB for `tiny` up to
  several GB for the large models) until you release it. On phones,
  release it when dictation ends rather than keeping it forever.
- One model stays resident per process; parking a different model
  replaces and frees the previous one. A request for a *different* model
  with `keepModelLoaded: false` leaves the parked one alone.
- Requests stay fully concurrent: a second transcription that arrives
  while the parked model is in use simply loads its own copy, exactly as
  before.

- The native engine is compiled with `-O3` on all platforms, including
  debug builds on iOS/macOS, Windows (`/O2`), and Linux — transcription
  speed there is close to release.
- Windows and Linux x64 builds target **AVX2** by default, like upstream
  whisper.cpp's standard x64 binaries (supported by virtually every x64 CPU
  since ~2013). For very old CPUs, build with `-DWHISPER_GGML_AVX2=OFF`.
- Android debug builds run the Dart layer in JIT mode; use `--release` for
  representative performance.
- The bundled whisper.cpp v1.9.1 is roughly **15× faster** than the engine
  in versions before 2.0.0.
