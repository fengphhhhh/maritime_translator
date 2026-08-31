# 离线模型目录

App 启动时会在这里查找 `MaritimeConfig.modelAssetPath` 指定的 ggml 模型。

模型文件本身**不纳入 Git**（`.gitignore` 已排除 `*.bin`）：large-v3-turbo 的 q5_0 量化版约 547 MB，远超仓库应该承载的体积。

## 获取默认模型

```bash
curl -L -o assets/models/ggml-large-v3-turbo-q5_0.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin
```

放好之后重新 `flutter run`，模型会随 App Bundle 一起打包，`AsrService` 直接从 Bundle 内读取，不额外复制一份到沙盒。

## 换用微调后的模型

两种方式，二选一：

1. **重新打包**：把新的 `.bin` 放进本目录，修改 `lib/config/maritime_config.dart` 里的 `modelAssetPath`，重新构建。
2. **免重编**：在 Xcode 中为 Runner 打开 `UIFileSharingEnabled`，通过「文件」App 把模型拷贝到本应用的 `Documents/models/` 目录，文件名与 `modelAssetPath` 的文件名一致即可。`AsrService` 会优先使用它。

## 体积提示

大模型会让 IPA 显著变大，且 App Store 单个应用有下载体积上限。如果最终要上架，通常的做法是首次启动时按需下载模型到 `Documents/models/`，而不是打进包里。
