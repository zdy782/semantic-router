---
title: Embeddings
description: Set up local or remote embeddings for semantic routing, caches, and vector stores.
---

Use embeddings for semantic matching, caches, memory, and vector stores.
Choose a local model or an OpenAI-compatible text embedding service. Merge
the relevant fragment below into your existing `config.yaml`.

## Local embeddings

This example selects the maintained mmBERT model, layer 22, and 768 dimensions:

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

Use a matching Candle or ORT image and include the model's required files.
For other model families and devices, see [In-process models](in-process.md).
Your embedding signals keep their existing candidates and thresholds.

### AMD GPU

The AMD serve default keeps semantic embeddings on CPU. To run mmBERT embeddings
on an AMD GPU, add this deployment and binding to the local configuration above:

```yaml
global:
  model_catalog:
    deployments:
      local-embedding:
        artifact: models/Vela-1.0-Encoder-307M-Embedding
        provider: ort
        device: rocm:0
        precision: native
        input:
          max_tokens: 1024
          overflow: reject
routing:
  model_bindings:
    embedding:
      deployment: local-embedding
      contract: embedding.v1
      adapter: mmbert
```

Use a ROCm image with the selected ONNX execution provider and a compatible
export. A graph using CK attention also needs the explicit
`custom_ops_profile: ck_flash_attention` deployment option. Keep `native`
precision to preserve the selected graph's math. A positive
`max_tokens` is required for GPU embeddings; choose a budget that fits your
workload and the model. This example rejects inputs beyond 1024 tokens.
Larger budgets increase preparation and inference cost. Classifiers have
their own deployment budgets; the default is 512 tokens.

## Input policy

Routing signals use representative samples by default. Set
`global.model_catalog.embeddings.semantic.embedding_config.full_context: true`
to send complete routing text to the loaded model. An explicit embedding
deployment's `input.max_tokens` sets its capacity; it does not override
`full_context: false`.

The deployment budget still must fit the artifact. A 32768-token budget is an
explicit opt-in for an appropriate export, not a claim of long-document
retrieval accuracy. Memory, response caches and vector stores retain their
own layer, dimension and input requirements.

Vela text embeddings use raw intermediate layers and the final-normalized full
layer, FP32 masked-mean pooling, then dimension truncation before L2
normalization. Preserve the artifact's representation metadata when exporting
or changing engines. Evaluate a shallower or narrower exit before making it
a latency optimization.

## Remote embeddings

Set the provider key in the Router environment:

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

Replace the URL, model, and dimensions with your provider's values. The Router
appends `/embeddings` to the base URL unless it is already present. Both dimension
settings must agree. Authentication uses a bearer token; the default response
limit is 16 MiB.

Remote embeddings support text only. They do not provide local tokenizer
windows, layer selection, image, or audio encoding. A configuration that needs
one of those features must use a compatible local model. The remote service
receives the text being embedded.

## Match the consumer's requirements

| Consumer | Check before changing the model |
| --- | --- |
| Semantic signals and model selectors | Matching thresholds and the trained embedding space |
| Vector stores and persistent caches | Stored representation identity, dimensions and re-ingestion requirements |
| In-memory mmBERT cache | Layer 6, dimension 256 must be available |
| Memory | Configured dimensions; mmBERT defaults to 256, multimodal to 384 |
| Response cache and RAG windows | Local tokenizer-window support |
| Image or audio features | A local model with the required encoder |

The Router binds supported local mmBERT stores and caches to the loaded
representation, including actual artifacts, effective layer/dimension and
input policy. Changing the space isolates persistent cache and memory data;
incompatible vector-store data requires re-ingestion. Old vectors are kept,
not adopted because their dimensions match. Remote mutable model identities
do not provide the same local-artifact guarantee.

Rebuild stored vectors when changing their embedding space, even if the new
model has the same output dimension. ORT exports must include every layer used
by enabled consumers. The Router warms these layers during startup; a missing
or invalid layer prevents activation.

## Start and inspect

```bash
vllm-sr config validate --config config.yaml
vllm-sr serve --config config.yaml
curl -fsS http://localhost:8080/startup-status | jq '.embedding_provider'
```

Startup checks the provider and vector dimensions. For test inputs, use
`POST /api/v1/diagnostics/embeddings`; request examples are in the
[API reference](../../api/apiserver.md). Status reports redact credentials.
