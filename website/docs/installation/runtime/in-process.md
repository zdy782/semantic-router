---
title: In-process models
description: Choose local engines and hardware, configure a classifier, and run it.
---

Run models inside the Router when you want local inference without another
model service. Install the CLI and a matching image using the
[installation guide](../installation.md).

## Choose an engine and model

| Engine | Hardware | Model format |
| --- | --- | --- |
| Candle | CPU (`cpu`), NVIDIA (`cuda:0`), Apple Metal (`metal:0`) | Compatible checkpoint weights; `native` or `fp32` precision |
| ONNX Runtime | CPU (`cpu`) | ONNX graph; `precision: native` |
| ONNX Runtime with ROCm | AMD GPU (`rocm:N`) | Compatible ONNX graph; `precision: native` preserves the graph’s precision |
| ONNX Runtime with MIGraphX | AMD GPU (`migraphx:N`) | Compatible ONNX graph; `native` or explicit `fp16` conversion |
| ML and NLP engines | CPU | Trained selectors or keyword-matching configuration |

Candle supports GPU index 0. BERT, merged BERT LoRA, and LoRA token models do
not support Metal. ORT accepts CPU, ROCm and MIGraphX devices; use Candle for
the NVIDIA and Metal options above. CUDA is a supported build path; CPU or AMD
results do not establish NVIDIA performance or model quality. The existing OpenVINO primary embedding integration remains a
separate platform setup, without a deployment provider or cache/window API.

| Model family | Supported uses |
| --- | --- |
| ModernBERT / mmBERT | Categorical classification, independent label scores, token spans and text embeddings |
| Compatible Vela Reranker artifact | Joint query/document relevance scoring for vectorstore RAG |
| BERT and merged BERT LoRA | Sequence/token classification; BERT text embeddings |
| DeBERTa | Sequence classification |
| Task-specific hallucination and NLI models | Grounding and sentence-pair checks with Candle |
| Qwen3 and Gemma embedding models | Text embeddings with Candle |
| Compatible multimodal models | Their available text, image, and audio encoders |
| MLP, KNN, K-means, SVM | Model selection from embedding features, on CPU |
| BM25 and N-gram | Keyword matching, on CPU |
| TextRank, TF-IDF, and heuristics | Prompt compression and rules in Go |

ORT supports exported mmBERT classifiers and mmBERT or multimodal embedding
graphs, plus compatible pair-scoring graphs. Local classifier budgets default
to **512 tokens**, including special tokens. An explicit deployment
`input.max_tokens` can select a larger budget up to the actual checkpoint and
graph capacity; zero preserves the existing default. A classifier needs a head and
labels trained for its task, such as domain, prompt guard, PII, fact-check,
feedback, or output modality. Qwen3/Gemma embedding models do not provide a
local generative classifier.

Sequence classification returns `label_distribution.v1`, whose probabilities
sum to one. Hazard detection uses `label_scores.v1`, whose scores are independent
and may sum above one. The loader checks the task head and its activation;
these contracts are not interchangeable.

For standalone independent-label routing, the generic classifier binding accepts
an explicit immutable operating-point sidecar with Candle float32 or a qualified
ORT native graph and execution provider. Its frozen
window and threshold policy replaces manually repeated threshold predicates;
see [Classifier signals](../../tutorials/signal/learned/classifier.md#independent-labels-with-a-frozen-operating-point).

For setup of other local features, see [Embeddings](embeddings.md),
[Safety models](safety.md), [MLP selection](../../tutorials/algorithm/selection/mlp.md),
and [Keyword signals](../../tutorials/signal/heuristic/keyword.md).

## Configure a classifier

The example below uses a custom email classifier on CPU. Before starting:

- Put a complete compatible checkpoint at `models/email-classifier`.
- Replace `BENIGN` and `PHISHING` with the checkpoint's labels, in their trained order.
- Replace the answer model's endpoint with one the Router can reach.

A **deployment** specifies the model files and engine. A **binding** connects
that deployment to the `email-risk` classifier rule. Save this as `config.yaml`:

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

## Start and test

```bash
vllm-sr config validate --config config.yaml
vllm-sr serve --config config.yaml
curl -sS http://localhost:8899/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{"model":"auto","messages":[{"role":"user","content":"Review this email requesting a password reset."}]}'
```

The rule matches when the classifier's phishing score is at least 0.8. This
example sends both matching and nonmatching requests to the same answer model;
change the decision's model or plugins to apply your policy.

## Change the engine or model

For an exported mmBERT ONNX model, change the deployment to `provider: ort`,
point `artifact` at its complete ONNX directory, and set the binding's
`adapter: mmbert` and `head: onnx/model.onnx`. Choose a device from the table above.

Custom model directories need no registry entry. Include the checkpoint or
ONNX graph, tokenizer, configuration, labels, and any external tensor files.
For LoRA models, supply complete merged weights rather than adapter deltas alone.
Registered models are downloaded by the normal serve workflow. Pin `revision`
and use a new directory when replacing a model that is already in use.

Bindings apply to one recipe. Put them in that recipe's `routing` block to
change its model without changing other recipes. See the
[configuration reference](../../api/configuration-schema.mdx) for all fields.

For a source build, use `make vllm-sr-dev`, then add
`--image-pull-policy never` to the serve command.

## Choose a long-input or AMD deployment

For a checkpoint and exported graph evaluated at 32K, an explicit deployment
can use the following settings. Merge this fragment into a configuration with
a compatible binding; it does not enable a task by itself.

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

For a native checkpoint on CPU, select `provider: candle` and `device: cpu`.
For a graph exported with CK attention, select its exact graph in the binding
and add `custom_ops_profile: ck_flash_attention` to the ROCm deployment. Plain
FP32 graphs do not require that profile. `native` means the graph's existing
math, including any mixed precision; it does not mean every operation is FP32.
GPU preparation rejects an unavailable provider or CPU fallback.

A larger budget does not improve accuracy by itself. It can substantially
increase CPU latency and GPU memory use. Keep short routing samples or a
validated [window policy](safety.md#native-classifier-context) unless the task
needs the complete input. Test quality and latency with the selected graph,
precision, length and padding pattern.

## Bind a RAG reranker

A reranker consumes query/document pairs after retrieval. It is not a routing
signal or a generation endpoint. In the recipe using vectorstore RAG, bind:

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

Enable `rerank` in that recipe's RAG plugin, as shown in the
[RAG guide](../../tutorials/plugin/rag.md#neural-reranking).
The deployment loads only when a reachable recipe uses it. Candle requires the
encoder weights, tokenizer, config, `matryoshka_config.json` and
`classification_heads.safetensors`. ORT needs a complete pair-scoring graph with
its declared layer, dimension and relevance-logit metadata.

The fixed exit must exist in the artifact. Scores are raw relevance logits,
not probabilities. The token budget covers both inputs and pair special tokens;
oversized pairs fail instead of being silently shortened.
