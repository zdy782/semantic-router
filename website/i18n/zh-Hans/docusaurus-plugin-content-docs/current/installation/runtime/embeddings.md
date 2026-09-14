---
title: 嵌入模型
description: 为语义路由、缓存和向量存储配置本地或远程嵌入模型。
translation:
  source_commit: "dc7f402642a8b8ecec8218e2086a4c6f186ea406"
  source_file: "docs/installation/runtime/embeddings.md"
  outdated: false
---

嵌入模型用于语义匹配、缓存、记忆和向量存储。选择本地模型或兼容 OpenAI API 的文本嵌入服务，将下面相应的片段合入现有 `config.yaml`。

## 本地嵌入 {#local-embeddings}

本例选择 Vela Embedding，使用第 22 层和 768 维向量：

```yaml
global:
  model_catalog:
    embeddings:
      semantic:
        embedding_config:
          model_type: mmbert
          preload_embeddings: true
          target_dimension: 768
          target_layer: 22
        mmbert_model_path: models/Vela-1.0-Encoder-307M-Embedding
```

使用匹配的 Candle 或 ORT 镜像，并准备模型所需文件。其他模型家族和设备见[进程内模型](in-process.md)。嵌入信号沿用现有候选文本和阈值。

### AMD GPU {#amd-gpu}

AMD serve 默认让语义嵌入在 CPU 上运行。显式选择已验证的 Vela CK 图时，在上述本地配置中添加以下 deployment 和 binding：

```yaml
global:
  model_catalog:
    deployments:
      local-embedding:
        artifact: models/Vela-1.0-Encoder-307M-Embedding
        revision: a72bbb73f1316553ddb915cff06e1fbc58f9af1c
        provider: ort
        device: rocm:0
        precision: native
        custom_ops_profile: ck_flash_attention
        input:
          max_tokens: 32768
          overflow: reject
routing:
  model_bindings:
    embedding:
      deployment: local-embedding
      contract: embedding.v1
      adapter: mmbert
      head: onnx/model_fa.onnx
```

使用包含 ORT ROCm 和 CK 自定义算子库的 AMD 镜像。所选计算图使用 native 精度，拒绝 CPU fallback。主图及配套的 `model_fa_layer_N.onnx` 平铺文件共享 `onnx/` 内的外部权重；保留所有已启用使用方需要的层。

GPU 必须设置正数预算。此部署拒绝超过 32,768 tokens（含特殊 token）的输入；独立 Embedding 执行已验证至该长度。路由需要完整文本时，按下文设置 `full_context: true`。输入可被接受并不代表检索质量已验证。

[Vela AMD 配方](https://github.com/vllm-project/semantic-router/blob/main/config/recipes/vela-amd/README.md)提供全部十个任务绑定。完整信号流水线使用 8K 分类器预算，并不声称所有分类器都完成了 AMD 32K 验证。

## 输入策略 {#input-policy}

路由信号默认使用代表性片段。设置 `global.model_catalog.embeddings.semantic.embedding_config.full_context: true`，可将完整路由文本传给已加载的模型。显式部署的 `input.max_tokens` 设置容量，不会覆盖 `full_context: false`。

部署预算仍须符合产物容量。32,768-token 预算是针对合适导出的显式选择，并不代表长文档检索准确率。Memory、响应缓存和 vector store 各有层数、维度及输入要求。

Vela 文本嵌入使用未做最终归一化的中间层，以及完成最终归一化的完整层；随后使用 FP32 masked-mean pooling，截取维度，再做 L2 归一化。导出或更换引擎时应保留表示元数据。在使用更浅或更窄的出口降低时延前，先进行评估。

## 远程嵌入 {#remote-embeddings}

在 Router 环境中设置服务密钥：

```bash
export EMBEDDING_API_KEY="<provider-key>"
```

```yaml
global:
  model_catalog:
    embeddings:
      semantic:
        embedding_config:
          backend: openai_compatible
          model_type: remote
          preload_embeddings: false
          target_dimension: 1536
        endpoint:
          base_url: https://embedding.example.com/v1
          model: text-embedding-model
          api_key_env: EMBEDDING_API_KEY
          timeout_seconds: 10
          max_retries: 2
          max_response_bytes: 16777216
          dimensions: 1536
```

将 URL、模型和维度替换为服务提供方的值。如果基础 URL 尚未以 `/embeddings` 结尾，Router 会添加该后缀。两处维度设置必须一致。认证使用 bearer token；默认响应大小上限为 16 MiB。

远程嵌入只支持文本，不提供本地分词器分窗、层选择、图像或音频编码。需要这些功能的配置必须使用兼容的本地模型。远程服务会接收到待嵌入的文本。

## 匹配使用方的要求 {#match-the-consumers-requirements}

| 使用方 | 更换模型前需要检查 |
| --- | --- |
| 语义信号和模型选择器 | 匹配阈值和训练时的嵌入空间 |
| 向量存储和持久化缓存 | 已存表示身份、维度及重新入库要求 |
| 内存 mmBERT 缓存 | 必须提供第 6 层、256 维向量 |
| 记忆 | 配置的维度；mmBERT 默认为 256，多模态模型默认为 384 |
| 响应缓存和 RAG 分窗 | 本地分词器分窗支持 |
| 图像或音频功能 | 本地模型包含所需编码器 |

Router 将支持的本地 mmBERT 存储和缓存绑定到已加载的表示，包括实际产物、有效层数/维度及输入策略。表示空间变化时，持久缓存和 memory 按身份隔离；不兼容的 vector store 数据需要重新入库。旧向量会保留，不会仅因维度相同就被接管。可变的远程模型身份不提供同样的本地产物保证。

嵌入空间改变后，应重建已存向量，即使新模型的输出维度相同。ORT 导出文件必须包含已启用功能使用的每一层。Router 在启动时对这些层预热；层缺失或无效会阻止配置激活。

## 启动并检查 {#start-and-inspect}

```bash
vllm-sr config validate --config config.yaml
vllm-sr serve --config config.yaml
curl -fsS http://localhost:8080/startup-status | jq '.embedding_provider'
```

启动时会检查服务或本地模型以及向量维度。要测试具体输入，使用 `POST /api/v1/diagnostics/embeddings`；请求示例见 [API 参考](/zh-Hans/docs/api/apiserver)。状态报告会隐藏凭据。
