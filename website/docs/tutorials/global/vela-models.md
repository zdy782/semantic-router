# Vela Router Models

## Overview

[Vela 1.0](https://huggingface.co/collections/llm-semantic-router/vela-10-router-models-6aa555ba70cc6997d6d67798)
is the model family for intelligent routing. Its eleven models share the Vela
307M encoder base and cover routing, prompt protection, content safety, retrieval
and reranking. The Router registry pins each release to an immutable revision.

| Model | Role |
| --- | --- |
| Encoder | Shared base for adapting new routing tasks |
| Domain | Request subject across 14 domains |
| Guard | Prompt injection and jailbreak detection |
| Safety | Unsafe content detection |
| Hazard | Twelve independent content risk categories |
| PII | Personal information spans across 17 entity types |
| FactCheck | Whether a request needs factual verification |
| Feedback | Four feedback types and a neutral `NO_FEEDBACK` class |
| Modality | Text, image, or combined output intent from a written request |
| Embedding | Multilingual retrieval and semantic matching |
| Reranker | Relevance scoring for query-document pairs |

The full model name is `Vela-1.0-Encoder-307M`, followed by the task suffix.
Modality classifies text requests; Vela 1.0 does not contain multimodal encoders.
FactCheck requests verification and does not verify the truth of an answer.

## What Problem Does It Solve?

A shared model family supplies task-specific signals and retrieval components
with explicit model identities, input budgets and serving policies.

## When to Use

Use Vela for built-in routing tasks or adapt the shared Encoder for a new task.
Choose input length and representation size against your workload's quality
and latency requirements.

## Defaults and input budgets

Built-in Domain, Guard, Safety, PII, FactCheck, Feedback and semantic Embedding
now use Vela. The reference configuration also selects Vela Modality, Hazard and
Reranker. Only models required by a recipe are loaded. The base encoder is a
training parent and is not loaded as an additional routing signal.

Default operating thresholds are **0.5** for Guard, **0.95** for FactCheck and
**0.7** for Feedback. `NO_FEEDBACK` emits no feedback match. Safety is independent
of Guard, so an unsafe content request need not be classified as a prompt attack.
Hazard uses per-label thresholds from its artifact-bound operating point; a
single threshold does not represent its published decision policy.

An input budget is a deployment choice. A module `max_sequence_length` of `0`
keeps the conservative 512-token policy. Embedding defaults to 22 layers,
768 dimensions and `full_context: false`. Explicit model bindings can accept
up to **32,768 tokens**, including special tokens, with `overflow: reject`.
A rejected input is not silently shortened.

## Configuration

The following excerpt binds Domain to a CPU deployment with a 32K budget. Apply
it to an existing configuration containing providers, signals and decisions.

```yaml
routing:
  model_bindings:
    domain_classifier:
      deployment: vela-domain
      contract: label_distribution.v1
      adapter: modernbert
      mapping_path: models/Vela-1.0-Encoder-307M-Domain/category_mapping.json

global:
  model_catalog:
    deployments:
      vela-domain:
        artifact: models/Vela-1.0-Encoder-307M-Domain
        provider: candle
        device: cpu
        precision: fp32
        input:
          max_tokens: 32768
          overflow: reject
```

Use the same deployment and consumer-binding structure for other classifiers.
PII returns `token_spans.v1`. Embedding uses the `mmbert` adapter and
`embedding.v1`; Reranker uses `vela_reranker` and `relevance_scores.v1`. These
adapter names describe inference architectures and are independent of release
names. See [in-process inference](/docs/installation/runtime/in-process) for the full contract.

For Hazard, bind the independent classifier contract `label_scores.v1` and pin
`operating_point.json` with its SHA-256. The policy binds the weights, tokenizer,
execution settings, overlapping windows and twelve thresholds. Decisions select
labels without replacing those thresholds. The reference configuration includes
this complete pattern.

PII's overlapping scan and Hazard's windowed policy differ from whole-document
classification. Select the policy appropriate to the task, and measure latency
with the input lengths your application will send.

## Inference engines and hardware

Native Vela artifacts run through Candle. CPU execution is validated, including
32K inputs. CUDA remains an available Candle backend; NVIDIA performance must be
measured on the target hardware.

ONNX is the portable inference format for the ORT provider. AMD GPU acceleration
uses the ROCm MIGraphX execution provider, so a CPU-only ONNX session is not AMD
GPU validation. Choose the graph and representation that match the deployment,
and check the actual provider, precision and fallback evidence. Initial GPU
compilation and warm request latency are separate measurements.

The Embedding and Reranker repositories include FP32 ONNX graphs with shared
external weights. The full representation uses `onnx/model.onnx`; reduced
representations require their matching trained layer or layer/dimension graph.
The downloader resolves a full-size selection from the model's encoder
configuration, so an explicit full selection can use the primary graph.
Replacing native weights also requires regenerating the corresponding ONNX
artifacts before publishing the update.

All models expose their supported input length, usage and comparable evaluation
results in their model cards. Published comparisons use the previous mmBERT
family on matched evaluation data. Quality scores, maximum accepted input length
and inference performance measure different properties.

## Verify live routing and reranking

Route Preview returns actual signal values, decisions and per-signal latency:

```bash
curl http://localhost:8080/api/v1/routing/preview?trace=true \
  -H 'Content-Type: application/json' \
  -d '{"model":"auto","text":"Help me debug this Python program."}'
```

Use the public model name declared by your entrypoint. Check `/ready` before
sending requests and inspect the returned signal values and evaluation trace.

Reranking executes inside the vectorstore RAG plugin after routing. Bind
`rag.reranker` and enable `rerank` as described in
[neural reranking](/docs/tutorials/plugin/rag#neural-reranking). Verify it through
a real chat request with indexed documents. Its request trace records candidate
count, reranker identity, relevance scores and reranking latency; routing Preview
does not execute the RAG plugin.

## Preserve an earlier deployment

Explicit older model paths and aliases retain their original repositories.
Select the matching mapping file, threshold and input policy when reproducing
an earlier classifier. Upgrading to Vela does not rewrite explicit model choices.

Changing embedding weights or representation changes the vector space. Response
caches and memory isolate data by representation identity. Existing vector stores
require compatible embeddings or reindexing; old data is not silently adopted
or deleted. See [stores and tools](./stores-and-tools.md).
