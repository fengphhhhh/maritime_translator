# 离线模型目录

App 启动时会在这里查找 `MaritimeConfig` 指定的两个模型文件：

| 用途 | 配置项 | 默认文件名 |
| --- | --- | --- |
| 语音识别 (Whisper) | `modelAssetPath` | `ggml-large-v3-turbo-q5_0.bin` |
| 离线翻译 (Qwen) | `llmModelAssetPath` | `qwen2.5-1.5b-instruct-q4_k_m.gguf` |

模型文件本身**不纳入 Git**（`.gitignore` 已排除 `*.bin` 与 `*.gguf`）：两个模型合计约 1.6 GB，远超仓库应该承载的体积。

## 获取默认模型

### Whisper ASR（约 547 MB）

```bash
curl -L -o assets/models/ggml-large-v3-turbo-q5_0.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin
```

### Qwen 翻译（约 1.1 GB）

```bash
curl -L -o assets/models/qwen2.5-1.5b-instruct-q4_k_m.gguf \
  https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf
```

放好之后重新 `flutter run`，模型会随 App Bundle 一起打包，服务层直接从 Bundle 内读取，不额外复制一份到沙盒。

## 换用微调后的模型

两种方式，二选一：

1. **重新打包**：把新的模型文件放进本目录，修改 `lib/config/maritime_config.dart` 里对应的 `modelAssetPath` / `llmModelAssetPath`，重新构建。
2. **免重编**：通过「文件」App 把模型拷贝到本应用的 `Documents/models/` 目录，文件名与配置项的文件名一致即可。`ModelLocator` 会优先使用它。

## 体积与内存提示

两个大模型会让 IPA 显著变大，且同时常驻内存时 iOS 更容易杀后台进程。App 已在退到后台时释放 ASR 与 LLM 权重，并在 `Runner.entitlements` 中申请了 `com.apple.developer.kernel.increased-memory-limit` 以争取更多前台内存。

如果最终要上架，通常的做法是首次启动时按需下载模型到 `Documents/models/`，而不是打进包里。
