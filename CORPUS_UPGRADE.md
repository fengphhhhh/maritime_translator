# 全量语料修订与离线软件接入

日期：2026-11-05。

## 交付内容

原始138_.json保持原样。138_revised.json为校订版，保留50个主题及全部1176个原条目位置，45条缺失中文已补齐。348个位置进行了明确的内容修订；连同角色前缀拆分及术语格式统一，共463个位置的英中字段有变化。逐项前后对照及原文件SHA-256保存在tool/corpus/revision_manifest.json。

海事通信按SMCP的清晰、简短、无歧义原则及相关术语校订，生活对话保留自然表达。该文件是编辑校订语料，不是逐字出自IMO的官方中译本。涉及原文事实不明、职级不明确、缺失操作条件的内容，采用明确的角色或条件表述重写，并记录修订原因；不把错误源句机械地保留成标准答案。

## 软件已经使用的内容

- 全部源条目均已归档进assets/corpus/maritime_dialogues.json。
- 将拆散的语句合并为1088个话轮/说明单元，每个都保留原主题ID和句号映射。其中938个完整、可独立表达的句对参与匹配和示例检索；简短应答、舞台说明、未独立成句的片段保留上下文，不独立触发译文。
- 完整原句精确命中时直接返回校订译文，问号与附加条件不会被近似匹配吞掉；同一输入对应多个不同译文时不强行挑选。
- 未命中时，本地最多检索两条相关示例交给Qwen参考。检索会限制问句/陈述、否定、左右舷和前后方向，并排除有数字的示例以降低数值串入风险。近似匹配本身不生成最终答案。
- 增补航路设计图、引航卡、接班、船舶供应商、贝位、分油机、车钟及气象等术语；移除非标准程序词组合的强制术语映射。
- Whisper使用精简的中英文领域词提示，加入从语料校订中筛出的专业词；不把1176句全部塞入识别提示，也不按相似句擅改识别出的数字和指令。
- 翻译后校验常见数字表达、左右舷、车钟挡位、船首/船尾通过关系及否定指令。不一致时保留原文供核对并提示重试。

## 离线与准确性验证边界

运行时采用本地Whisper、本地Qwen、编译进App的词句库，无新增联网识别或云翻译。文本修订、热词及检索增强已经接入源码；没有更新模型权重，也没有声称完成语音声学微调。真实口音、VHF噪声下的识别改善，需要带正确逐字稿的实际录音及iPhone真机对照测试。

本轮执行应用测试、独立离线回归及全语料覆盖检查。数字和关键语义检查对938个可独立句对未报告不一致。检查是确定性规则，不等于完整语义正确性证明。额外的Windows模型样例验证未稳定完成，未将其计作模型准确率通过；未进行iOS原生编译或签名安装。

## 后续构建

在Mac上按OFFLINE_BUILD.md构建并签名安装。两个离线模型已位于assets/models；开发机或CI可运行下载脚本复现固定版本。首次运行不依赖网络下载模型。

语料后续修订以assets/corpus/maritime_dialogues.json为源，执行：

```sh
node tool/corpus/build_corpus.mjs
flutter analyze
flutter test
dart tool/offline_regression.dart
```

检查生成的lib/config/maritime_corpus.dart和话轮JSON与源数据一致。训练与测试材料应分开，不能将句库自身的命中率称作真实场景准确率。

## 核验资料

- [IMO SMCP决议公开文本](https://puc.overheid.nl/nsi/doc/PUC_1418_14/1/)：消息类型、专业术语及车钟。
- [加拿大海岸警卫队无线电话程序](https://www.canada.ca/en/canadian-coast-guard/corporate/publications/radio-aids-marine-navigation/general.html)：结束与等待答复的程序词。
- [NOAA海洋气候资料](https://www.nhc.noaa.gov/marine/outreach/marine_climo.php)：Pilot Charts含义。
- [英国MCA 2026封闭处所说明](https://www.gov.uk/government/publications/mgn-659-mf-amendment-3-entry-into-enclosed-spaces/mgn-659-mf-amendment-3-the-merchant-shipping-and-fishing-vessels-entry-into-enclosed-spaces-regulations-2022)：修订气体检测、呼吸器及通风相关源句时的参考。
