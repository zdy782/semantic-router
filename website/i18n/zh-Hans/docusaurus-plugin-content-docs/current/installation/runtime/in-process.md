---
title: 进程内模型
description: 选择本地引擎和硬件，配置并运行分类器。
translation:
  source_commit: "70535875c9e1306b8f43212944cb8902f2a203f9"
  source_file: "docs/installation/runtime/in-process.md"
  outdated: false
---

如果希望在本地推理且不另建模型服务，可以在 Router 进程内运行模型。先按照[安装指南](/zh-Hans/docs/installation/)安装 CLI 和匹配的镜像。

## 选择引擎和模型 {#choose-an-engine-and-model}

| 引擎 | 硬件 | 模型格式 |
| --- | --- | --- |
| Candle | CPU（`cpu`）、NVIDIA（`cuda:0`）、Apple Metal（`metal:0`） | 兼容的模型权重；精度为 `native` 或 `fp32` |
| ONNX Runtime | CPU（`cpu`） | ONNX 图；使用 `precision: native` |
| ONNX Runtime with ROCm | AMD GPU（`rocm:N`） | 兼容 ONNX 图；`precision: native` 保留图的精度 |
| ONNX Runtime with MIGraphX | AMD GPU（`migraphx:N`） | 兼容的 ONNX 图；精度为 `native` 或 `fp16` |
| ML 和 NLP 引擎 | CPU | 已训练的选择器或关键词匹配配置 |

Candle 支持 GPU 索引 0。BERT、已合并的 BERT LoRA 和 LoRA token 模型不支持 Metal。ORT 接受 CPU、ROCm 和 MIGraphX 设备；上表中的 NVIDIA 和 Metal 选项使用 Candle。CUDA 是可用构建路径，但 CPU 或 AMD 结果不能证明 NVIDIA 性能或模型质量。现有 OpenVINO 主嵌入模型集成仍采用单独的平台配置，不提供 deployment provider 或缓存/分窗 API。

| 模型家族 | 支持的用途 |
| --- | --- |
| ModernBERT / mmBERT | 类别分类、独立标签分数、token spans 和文本嵌入 |
| 兼容的 Vela Reranker 产物 | vectorstore RAG 的查询/文档联合相关性评分 |
| BERT 和已合并的 BERT LoRA | 序列分类和 token 分类；BERT 文本嵌入 |
| DeBERTa | 序列分类 |
| 专用幻觉检测和 NLI 模型 | 使用 Candle 检查内容依据和句对关系 |
| Qwen3 和 Gemma 嵌入模型 | 使用 Candle 生成文本嵌入 |
| 兼容的多模态模型 | 模型实际提供的文本、图像和音频编码器 |
| MLP、KNN、K-means、SVM | 在 CPU 上根据嵌入特征选择模型 |
| BM25 和 N-gram | 在 CPU 上匹配关键词 |
| TextRank、TF-IDF 和启发式方法 | 在 Go 中执行提示词压缩和规则 |

ORT 支持导出的 mmBERT 分类图、mmBERT 或多模态嵌入图，以及兼容的句对评分图。本地分类器输入预算默认 **512 tokens**，含特殊 token。显式 deployment 的 `input.max_tokens` 可选择不超过实际 checkpoint 与计算图容量的更大预算；零保留原有默认值。分类器需要针对任务训练的分类头和标签，例如领域、提示词防护、PII、事实核查、反馈或输出模态。Qwen3/Gemma 嵌入模型不提供本地生成式分类功能。

序列分类返回 `label_distribution.v1`，其概率之和为一。Hazard 使用 `label_scores.v1`，各分数独立，总和可以超过一。加载器检查任务头及其激活方式；这两个契约不能互换。

对于独立标签路由，通用 classifier binding 接受显式不可变的 operating-point sidecar，使用 Candle float32 或已验证的 ORT native 图与执行 provider。其冻结的窗口与阈值策略替代手动重复的阈值谓词，详见[分类器信号](../../tutorials/signal/learned/classifier.md#independent-labels-with-a-frozen-operating-point)。

其他本地功能的配置见[嵌入模型](embeddings.md)、[安全模型](safety.md)、[MLP 选择](/zh-Hans/docs/tutorials/algorithm/selection/mlp)和[关键词信号](/zh-Hans/docs/tutorials/signal/heuristic/keyword)。

## 配置分类器 {#configure-a-classifier}

下面的示例在 CPU 上运行自定义邮件分类器。开始前请准备：

- 将完整且兼容的模型文件放到 `models/email-classifier`。
- 将 `BENIGN` 和 `PHISHING` 替换为模型的标签，并保持训练时的顺序。
- 将回答模型的地址替换为 Router 可以访问的地址。

**deployment** 指定模型文件和引擎。**binding** 将该部署连接到 `email-risk` 分类规则。将以下内容保存为 `config.yaml`：

```yaml
version: v0.3
listeners:
  - name: http
    address: 0.0.0.0
    port: 8899
providers:
  defaults:
    model: answer-model
  models:
    - name: answer-model
      backend_refs:
        - name: answer
          endpoint: 127.0.0.1:8000
          protocol: http
routing:
  model_bindings:
    classifier.email-risk:
      deployment: email-risk-cpu
      contract: label_distribution.v1
      adapter: auto
  signals:
    classifiers:
      - name: email-risk
        type: local
        labels: [BENIGN, PHISHING]
  decisions:
    - name: inspect-email
      priority: 100
      rules:
        operator: AND
        on_unknown: fail_request
        conditions:
          - type: classifier
            name: email-risk
            label: PHISHING
            predicate:
              gte: 0.8
      modelRefs:
        - model: answer-model
global:
  model_catalog:
    deployments:
      email-risk-cpu:
        artifact: models/email-classifier
        provider: candle
        device: cpu
        precision: native
        input:
          max_tokens: 512
          overflow: reject
```

## 启动并测试 {#start-and-test}

```bash
vllm-sr config validate --config config.yaml
vllm-sr serve --config config.yaml
curl -sS http://localhost:8899/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{"model":"auto","messages":[{"role":"user","content":"Review this email requesting a password reset."}]}'
```

当分类器的钓鱼邮件分数达到 0.8 时，这条规则匹配。示例将匹配和不匹配的请求都发送给同一个回答模型；修改决策中的模型或插件，即可执行自己的策略。

## 更换引擎或模型 {#change-the-engine-or-model}

对于导出的 mmBERT ONNX 模型，将部署改为 `provider: ort`，让 `artifact` 指向完整的 ONNX 目录，并在 binding 中设置 `adapter: mmbert` 和 `head: onnx/model.onnx`。设备从上表中选择。

自定义模型目录不需要注册表条目。目录应包含权重或 ONNX 图、分词器、配置、标签以及图引用的外部张量文件。LoRA 模型需要完整的已合并权重，不能只提供 adapter 增量。已注册模型由正常的 serve 流程下载。替换正在使用的模型时，固定 `revision` 并使用新目录。

Binding 仅对一个配方生效。将它放入对应配方的 `routing` 块，即可更换该配方的模型而不影响其他配方。完整字段见[配置参考](/zh-Hans/docs/api/configuration-schema)。

从源码构建时，先运行 `make vllm-sr-dev`，再为 serve 命令添加 `--image-pull-policy never`。

## 选择长输入或 AMD 部署 {#choose-a-long-input-or-amd-deployment}

完整示例见 [Vela AMD 配方](https://github.com/vllm-project/semantic-router/blob/main/config/recipes/vela-amd/README.md)。它固定十个任务模型，Embedding/Reranker 使用 CK ROCm，分类器使用 MIGraphX；通过 `vela-auto` 访问服务名为 `vela-default` 的后端。全部信号的 Preview 预算为 8K。独立 Embedding/Reranker 执行已验证至 32K；Hazard 保留与产物绑定的 2,048-token 窗口及 32K 逻辑策略。这不代表所有分类器完成了 AMD 32K 验证。`--platform amd` 选择镜像和设备；显式 binding 决定模型位置，也保留操作者配置的 CPU 部署。

对于其他已在 32K 验证的 checkpoint 和导出图，可使用以下显式部署。将片段合入包含兼容 binding 的配置；它本身不会启用任务。

```yaml
global:
  model_catalog:
    deployments:
      long-classifier:
        artifact: models/long-classifier
        provider: ort
        device: rocm:0
        precision: native
        input:
          max_tokens: 32768
          overflow: reject
```

CPU 原生 checkpoint 使用 `provider: candle` 和 `device: cpu`。对 CK attention 导出图，在 binding 中选择精确的计算图，并在 ROCm deployment 中添加 `custom_ops_profile: ck_flash_attention`。Vela Embedding 和 Reranker 的完整 22/768 表示使用 `head: onnx/model_fa.onnx`。缩减 Reranker 使用 `onnx/model_fa_layer_N_dim_D.onnx`，并匹配 `pair_scorer.layer` / `pair_scorer.dimension`；加载时会检查图元数据。可移植图与 CK 图不能混用。普通 FP32 图不需要该 profile。`native` 表示保留图本身的计算精度，包括混合精度，并非每个算子都是 FP32。GPU 准备过程拒绝不可用的 provider 或 CPU fallback。

使用 `provider: ort`、`device: migraphx:0` 时，可在 deployment 中设置 `compilation_cache_dir: /var/cache/semantic-router/migraphx`。将该绝对路径挂载为持久可写目录，置于模型及计算图目录之外。默认禁用编译缓存；CPU、Candle、HTTP 和普通 ROCm deployment 不接受此选项。

缓存区分计算图与外部权重内容、精度、执行 shape、运行时/编译器库、GPU 身份和编译器设置。身份匹配时，新进程可以复用经过验证的编译程序；新身份仍需冷编译。缓存不会启用 CPU fallback，也不会改变输入限制或准确率要求。运行时拒绝冲突的全局缓存环境设置，不会将其与 deployment 选项混合。

更大的预算本身不会提高准确率，却可能显著增加 CPU 时延和 GPU 内存占用。除非任务需要完整输入，否则保留短路由样本或已验证的[窗口策略](safety.md#native-classifier-context)。根据所选图、精度、长度和 padding 模式测试质量及时延。

## 绑定 RAG reranker {#bind-a-rag-reranker}

Reranker 在检索后处理查询/文档对，不是路由信号或生成端点。在使用 vectorstore RAG 的配方中绑定：

```yaml
routing:
  model_bindings:
    rag.reranker:
      deployment: document-ranker
      contract: relevance_scores.v1
      adapter: vela_reranker
      pair_scorer:
        layer: 22
        dimension: 768
global:
  model_catalog:
    deployments:
      document-ranker:
        artifact: models/document-ranker
        provider: candle
        device: cpu
        precision: native
        input:
          max_tokens: 4096
          overflow: reject
```

在同一配方的 RAG 插件中启用 `rerank`，示例见 [RAG 指南](../../tutorials/plugin/rag.md#neural-reranking)。只有可达配方实际使用时才会加载 deployment。Candle 需要编码器权重、tokenizer、config、`matryoshka_config.json` 和 `classification_heads.safetensors`；ORT 需要完整的句对评分图，并声明层数、维度和 relevance-logit 元数据。

固定出口必须存在于产物中。分数是原始相关性 logit，不是概率。Token 预算包含两段输入和句对特殊 token；超限句对会失败，不会静默缩短。
