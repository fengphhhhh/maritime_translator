# 离线改进与 iPhone 17 Pro Max 验证

本次修改保留 Flutter、whisper.cpp 和 llama.cpp 的本地推理架构。App 运行时不下载模型，不上传录音或文本；下载脚本仅供开发、打包使用。

## 已修改

- 中英文使用各自的精简航海提示词，避免整份热词表挤占 Whisper 的提示空间。
- Whisper 使用 5 路束搜索。准确性和延迟的取舍需要在目标手机上测量。
- 录音进入识别前检查近乎数字静音，避免无声录音触发模型生成文字。这个能量检查不能区分人声与驾驶台噪声，也不是神经网络降噪。
- 翻译只注入本句相关的最多 16 项术语，取消译后机械字符串替换。上下文由 1024 扩至 4096 token，最大输出由 192 扩至 512 token。
- 14 条固定指令可以双向精确匹配，不经过生成模型。否定、条件、问号或其他附加词不做近似匹配。
- 校验译文中的阿拉伯数字，包括小数、前导零及重复次数；不一致就报错。此检查不能验证口述数字、数值与对象是否对应或整句语义。
- 超过 900 字符的输入要求分句；原生层检测输出达到上限而未正常结束的情况，禁止把半句作为完整译文显示。
- 切后台时等待正在运行的推理结束后再释放模型；作废的会话不能覆盖后续会话。
- 模型定位检查文件头及最低大小；下载脚本固定发布版本并验证完整 SHA-256。发布流程加入模型和代码检查。

## 模型准备

项目 `assets/models/` 使用以下文件：

- `ggml-large-v3-turbo-q5_0.bin`：574,041,195 字节。
- `qwen2.5-1.5b-instruct-q4_k_m.gguf`：1,117,320,736 字节。

在 Windows 或 Mac PowerShell 中运行 `./tool/download_models.ps1` 会下载、验证并放入正确位置，已验证的文件会跳过。对应发布来源和固定 SHA-256 在脚本中。不要将模型提交到 Git。

## Mac 编译及安装

需要满足 `pubspec.yaml` 中 Dart ^3.13.2 要求的 Flutter、支持手机当前 iOS 的 Xcode、Apple 签名身份和目标手机。

```sh
flutter pub get
dart tool/offline_regression.dart
dart tool/check_offline_models.dart
flutter analyze
flutter test
cd ios
pod install
cd ..
flutter run --release -d <设备ID>
```

或用 Xcode 打开 `ios/Runner.xcworkspace`，设置自己的签名团队后运行。已有 GitHub 构建流程会获取校验后的模型，并生成未签名 IPA；它仍须签名才能安装，不能等同于已通过真机验证的发布包。

## 沿用 GitHub 在线打包

对应仓库：https://github.com/fengphhhhh/maritime_translator 。工作流是 `.github/workflows/main.yml`，名称为 `Build iOS IPA`。

推送到 `main` 或 `codex/offline-maritime-accuracy` 会自动打包；也可以在 Actions 中手动运行工作流。此次固定 Flutter 3.47.9，与本地检查使用的版本一致。GitHub 打包时联网获取两个固定版本的模型，App 运行时仍使用包内文件离线识别和翻译。

工作流在上传前会读取最终 IPA，检查两个模型的完整 SHA-256，以及两份语料是否与本次校订文件一致。缺失或损坏时构建失败，不上传可下载的 IPA。成功后下载 `Maritime_Translator_App` 构建产物，解压得到 `app.ipa`，沿用原来的签名安装方式。模型合计约 1.69 GB，新 IPA 会明显大于原来的 14 MB 安装包；不要将模型文件、`.tools` 或本地开发缓存上传到源码仓库。

## 真机验收

1. 安装包含两个模型的新构建，确认 ASR/LLM 就绪。
2. 开飞行模式，另行关闭 Wi-Fi，重启 App 后测试两个翻译方向。
3. 先测固定指令，再测自由对话，重点测试左右舷、否定、疑问、条件、船名、呼号、坐标、090 等前导零、小数、VHF 频道。
4. 使用同一批安静环境和驾驶台/VHF 噪声录音，对比旧版与新版。记录英文词错率、中文字符错率、术语正确率、数字正确率、整句语义和延迟，不用少数演示句代替准确率统计。
5. 测短句、长句、安静说话、连续通话，以及识别/翻译中锁屏、切后台再返回。
6. 观察连续使用的温度、峰值内存和耗电，再决定束搜索大小及模型是否需要顺序驻留。

当前 Windows 上的逻辑检查不能替代 Xcode 原生编译和 iPhone 真机测量；本次没有据此声称达到某个识别率或翻译正确率。

## 本轮已执行的检查

- Flutter 应用测试：32 项通过。
- 独立离线逻辑回归检查：50 项通过。
- 两个模型：完整 SHA-256 校验通过，文件头与大小检查通过。
- 未进行 iOS 原生编译、真实模型推理准确率基准及 iPhone 真机测试。


全量语料校订和新翻译路径详见 [CORPUS_UPGRADE.md](CORPUS_UPGRADE.md)。
