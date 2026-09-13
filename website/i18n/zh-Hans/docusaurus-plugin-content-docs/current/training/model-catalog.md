---
title: 当前模型目录
sidebar_label: 模型目录
translation:
  source_commit: "e8c4109fd4151ad0c7c0163c8ead375bef882ddf"
  source_file: "docs/training/model-catalog.md"
  outdated: false
---

# 当前模型目录 {#current-model-catalog}

## Vela 1.0 {#vela-10}

Vela 是当前的 Router 模型家族，十一个模型共享已发布的 Vela Encoder 基座。各任务仓库包含推理所需文件；训练和评测工具保留在本代码仓库。

| 模型 | 用途 |
| --- | --- |
| [Encoder](https://huggingface.co/llm-semantic-router/Vela-1.0-Encoder-307M) | 新任务适配的共享基座 |
| [Domain](https://huggingface.co/llm-semantic-router/Vela-1.0-Encoder-307M-Domain) | 14 类请求主题 |
| [Guard](https://huggingface.co/llm-semantic-router/Vela-1.0-Encoder-307M-Guard) | 提示注入与越狱攻击 |
| [Safety](https://huggingface.co/llm-semantic-router/Vela-1.0-Encoder-307M-Safety) | 不安全内容 |
| [Hazard](https://huggingface.co/llm-semantic-router/Vela-1.0-Encoder-307M-Hazard) | 12 类独立内容风险 |
| [PII](https://huggingface.co/llm-semantic-router/Vela-1.0-Encoder-307M-PII) | 17 类个人信息实体 |
| [FactCheck](https://huggingface.co/llm-semantic-router/Vela-1.0-Encoder-307M-FactCheck) | 是否需要事实核查 |
| [Feedback](https://huggingface.co/llm-semantic-router/Vela-1.0-Encoder-307M-Feedback) | 四类反馈和 NO_FEEDBACK |
| [Modality](https://huggingface.co/llm-semantic-router/Vela-1.0-Encoder-307M-Modality) | 文本、图像或混合输出意图 |
| [Embedding](https://huggingface.co/llm-semantic-router/Vela-1.0-Encoder-307M-Embedding) | 多语言检索，20 种层数与维度组合 |
| [Reranker](https://huggingface.co/llm-semantic-router/Vela-1.0-Encoder-307M-Reranker) | 查询文档相关性，20 个层数与维度打分头 |

默认值、输入预算、硬件与实际验证见 [Vela 运行时配置](/docs/tutorials/global/vela-models)。模型卡片提供 quickstart，以及相对旧 mmBERT 家族的匹配评测。

## 旧 mmBERT 和多模态模型 {#previous-mmbert-and-multimodal-models}

以下表格保留此前的[嵌入](https://huggingface.co/collections/llm-semantic-router/mom-multilingual-embed)和[分类器](https://huggingface.co/collections/llm-semantic-router/mom-multilingual-class)集合及其原始训练工作流。对应基座和数据配方描述的是这些旧版本，并非当前 Vela 的训练血缘。多模态模型与 Vela 1.0 分开发布。

### 旧嵌入与重排序产物 {#earlier-embedding-and-reranking-artifacts}

| 逻辑模型 | 已发布产物 | 架构 | 训练方法 |
| --- | --- | --- | --- |
| mmBERT-32K 基础 | [`mmbert-32k-yarn`](https://huggingface.co/llm-semantic-router/mmbert-32k-yarn) | 带 32K YaRN 上下文的 ModernBERT 掩码语言编码器 | 持续多语言掩码语言建模 |
| mmBERT-32K embedder | [`mmbert-embed-32k-2d-matryoshka`](https://huggingface.co/llm-semantic-router/mmbert-embed-32k-2d-matryoshka) | 可选层和维度的 Bi-encoder 嵌入 | 带 2D Matryoshka 监督的 multiple-negatives ranking |
| mmBERT-32K reranker | [`mmbert-rerank-32k-2d-matryoshka`](https://huggingface.co/llm-semantic-router/mmbert-rerank-32k-2d-matryoshka) | 带 20 个层/维度打分头的 Cross-encoder | 在所有头上平均的二元相关性损失 |
| 小型多模态 embedder | [`multi-modal-embed-small`](https://huggingface.co/llm-semantic-router/multi-modal-embed-small) | MiniLM、SigLIP 和 Whisper-tiny 塔加两层融合；384 维 | 分阶段图文和音文对比对齐，带 Matryoshka 损失 |
| 大型多模态 embedder | [`multi-modal-embed-large`](https://huggingface.co/llm-semantic-router/multi-modal-embed-large) | mmBERT-32K、SigLIP2-SO400M 和 Whisper-medium 三编码器；768 维 | 带难负例的缓存混合负例排序 |

数据流、目标、配置和命令见 [mmBERT-32K 模型](./mmbert-32k-models) 和[多模态嵌入](./multimodal-embeddings)。

### 旧分类器产物 {#earlier-classifier-artifacts}

下面前六个分类器使用多语言 mmBERT-32K/ModernBERT 编码器。两个已发布的安全产物使用 `jhu-clsp/mmBERT-base`；当前安全工作流可以训练 32K 后继产物。序列分类器为请求预测一个标签；PII 模型为每个 token 预测一个 BIO 标签。

| 逻辑模型 | 标签或输出 | 已发布产物 | 训练方法 |
| --- | --- | --- | --- |
| 意图分类器 | 14 个学科领域 | [`merged`](https://huggingface.co/llm-semantic-router/mmbert32k-intent-classifier-merged)、[`LoRA`](https://huggingface.co/llm-semantic-router/mmbert32k-intent-classifier-lora) | 在 MMLU-Pro 加上回退意图样本上做 LoRA 序列分类 |
| 越狱检测器 | `benign`、`jailbreak` | [`merged`](https://huggingface.co/llm-semantic-router/mmbert32k-jailbreak-detector-merged)、[`LoRA`](https://huggingface.co/llm-semantic-router/mmbert32k-jailbreak-detector-lora) | 在良性/有毒聊天、攻击数据和模式增强上做 LoRA 序列分类 |
| 反馈检测器 | 四种反馈状态 | [`merged`](https://huggingface.co/llm-semantic-router/mmbert32k-feedback-detector-merged)、[`LoRA`](https://huggingface.co/llm-semantic-router/mmbert32k-feedback-detector-lora) | 类别加权的 LoRA 序列分类 |
| 模态路由器 | `AR`、`DIFFUSION`、`BOTH` | [`merged`](https://huggingface.co/llm-semantic-router/mmbert32k-modality-router-merged)、[`LoRA`](https://huggingface.co/llm-semantic-router/mmbert32k-modality-router-lora) | 带 focal loss、类别平衡和可选合成混合模态提示词的 LoRA |
| 事实核查分类器 | `FACT_CHECK_NEEDED`、`NO_FACT_CHECK_NEEDED` | [`merged`](https://huggingface.co/llm-semantic-router/mmbert32k-factcheck-classifier-merged)、[`LoRA`](https://huggingface.co/llm-semantic-router/mmbert32k-factcheck-classifier-lora) | 在信息寻求和非信息寻求提示词上做平衡 LoRA 序列分类 |
| PII 检测器 | 17 种实体类型，由 35 个 BIO 标签表示 | [`merged`](https://huggingface.co/llm-semantic-router/mmbert32k-pii-detector-merged)、[`LoRA`](https://huggingface.co/llm-semantic-router/mmbert32k-pii-detector-lora) | 带字符偏移到 token 对齐的 LoRA token 分类 |
| 安全 Level 1 | `safe`、`unsafe` | [`LoRA adapter`](https://huggingface.co/llm-semantic-router/mmbert-safety-binary-merged) | 确定性仅提示词的 LoRA 序列分类 |
| 安全 Level 2 | 九种危害输出 | [`LoRA`](https://huggingface.co/llm-semantic-router/mmbert-safety-binary-hazard) | 带固定分类对照的确定性仅提示词 LoRA 序列分类 |

前六个任务见[分类器模型](./classifier-models)，两级安全流水线见[安全分类器](./mmbert-safety-classifier)。

## 选择旧模型发布形态 {#choose-an-earlier-release-shape}

当运行时期望独立 Transformers 模型时，使用合并产物。当运行时可以加载 PEFT adapter 且你想要更小的任务专用产物时，使用 LoRA 产物。两种形态都必须保留训练时使用的同一分词器、标签顺序、基础模型兼容性和预处理契约。

Model Card 描述已发布权重。仓库中已核对的训练配置描述新运行。两者不同时，将发布视为已有产物，将树内配置视为再训练的事实来源；没有原始数据和运行回执时，不要假设新检查点会逐位相同。

Level 1 安全产物是 PEFT adapter，即使其历史名称以 `-merged` 结尾。检查产物内容和元数据，而不是从后缀推断加载方法。
