# Vela Router Models

## Overview

Router uses Vela for its built-in Domain, PII, FactCheck, Feedback and text
Embedding models. The reference configuration also selects Vela Modality.
The inference selectors remain `mmbert` and `mmbert32k`; they identify the
architecture, not the model release. Built-in downloads use immutable revisions
from the Router model registry.

## What Problem Does It Solve?

A shared model family supplies task-specific routing signals while keeping
model identity, input policy and serving thresholds explicit. Upgrading weights
does not by itself justify processing longer inputs on every request.

## When to Use

Use the built-in defaults for ordinary routing. Preserve an explicit older model
when reproducing its behavior, and opt into long-context inference only for
workloads whose measured quality and latency justify processing complete text.

This migration preserves the existing input policies. A classifier
`max_sequence_length` of `0` retains the 512-token budget; routing signals keep
their representative sampling and PII keeps its overlapping scans. Embedding
defaults to 22 layers and 768 dimensions, with `full_context: false`. FactCheck
uses the Vela development-selected threshold of **0.85**. Feedback retains its
**0.7** confidence policy and supports the `NO_FEEDBACK` class without emitting
a feedback match.

Guard keeps its existing model while Vela Guard, Safety and Hazard complete
release qualification. Safety and Hazard already have recipe-scoped runtime
bindings and a [Safety signal](../signal/learned/safety.md); compatible artifacts
can be configured explicitly.

Vela Reranker is integrated with the vectorstore RAG plugin. Bind a local pair
scorer through `rag.reranker` and enable the plugin's `rerank` setting, as shown
in [neural reranking](../plugin/rag.md#neural-reranking). It scores retrieved
query/document pairs during a live request. Route preview reports routing
signals and their latency; actual reranker timing comes from the RAG request
trace. An encoder Base is a training parent, not an additional routing signal.

## Configuration

### Keep an explicit older model

Existing model paths and aliases keep their original repositories. An explicit
configuration is not automatically rewritten to Vela. When selecting an older
classifier, keep its corresponding mapping path, input budget and threshold
together. For example, this override preserves the older Domain model:

```yaml
global:
  model_catalog:
    system:
      domain_classifier: models/mmbert32k-intent-classifier-merged
    modules:
      classifier:
        domain:
          category_mapping_path: models/mmbert32k-intent-classifier-merged/category_mapping.json
          max_sequence_length: 0
          threshold: 0.5
```

Changing embedding weights changes the vector space even when both models
produce 768 dimensions. Local mmBERT response caches and memory use the loaded
representation identity to isolate persistent data. Existing vector stores
require compatible embeddings or reindexing; old data is not silently adopted
or deleted. See [stores and tools](./stores-and-tools.md).

### Opt into long-context inference

Apply the following `global.model_catalog` settings to an existing, complete
deployment configuration. Keep its providers, signals and decisions. This is a
configuration excerpt, not a standalone routing recipe. Only enable the model
modules your decisions use.

```yaml
global:
  model_catalog:
    embeddings:
      semantic:
        mmbert_model_path: models/Vela-1.0-Encoder-307M-Embedding
        use_cpu: false
        embedding_config:
          model_type: mmbert
          target_layer: 22
          target_dimension: 768
          full_context: true
    system:
      domain_classifier: models/Vela-1.0-Encoder-307M-Domain
      pii_classifier: models/Vela-1.0-Encoder-307M-PII
      fact_check_classifier: models/Vela-1.0-Encoder-307M-FactCheck
      feedback_detector: models/Vela-1.0-Encoder-307M-Feedback
    modules:
      classifier:
        domain:
          model_ref: domain_classifier
          variant: mmbert32k
          category_mapping_path: models/Vela-1.0-Encoder-307M-Domain/category_mapping.json
          max_sequence_length: 32768
          use_cpu: false
        pii:
          model_ref: pii_classifier
          use_mmbert_32k: true
          pii_mapping_path: models/Vela-1.0-Encoder-307M-PII/pii_mapping.json
          max_sequence_length: 0
          use_cpu: false
      hallucination_mitigation:
        fact_check:
          model_ref: fact_check_classifier
          use_mmbert_32k: true
          threshold: 0.85
          max_sequence_length: 32768
          use_cpu: false
      feedback_detector:
        model_ref: feedback_detector
        use_mmbert_32k: true
        threshold: 0.7
        max_sequence_length: 32768
        use_cpu: false
      modality_detector:
        enabled: true
        method: classifier
        confidence_threshold: 0.7
        classifier:
          model_path: models/Vela-1.0-Encoder-307M-Modality
          max_sequence_length: 32768
          use_cpu: false
```

Validate the complete file, then use the existing AMD local-image flow:

```bash
vllm-sr config validate --config config.yaml
vllm-sr serve --config config.yaml --platform amd --image-pull-policy never
```

These settings send full selected routing text to Domain, FactCheck, Feedback,
Modality and Embedding. Native token budgets include special tokens, and
over-budget inference is rejected rather than silently truncated. PII remains
on its existing scan policy; setting its budget above 512 opts into one-pass
whole-document inference and changes that detection policy. Model capacity does
not guarantee entity recall, calibrated confidence, or bounded route latency.

Long-input support is task and engine specific. FactCheck's published 32K
stress slice achieved 8/12 correct at 0.85. Feedback retains long-context
false-positive limitations. The Embedding natural-document final reached
21,816 tokens; exact 32K coverage also includes constructed and engineering
fixtures. Find each model's usage and capabilities in the
[Vela collection](https://huggingface.co/collections/llm-semantic-router/vela-10-router-models-6aa555ba70cc6997d6d67798).

CPU and AMD evidence should not be interchanged. The full-layer Embedding
Candle CPU 32K run verifies functionality; it does not establish an interactive
routing latency. Controlled eight-thread CPU runs at 512 and 2K tokens measured
1.26× and 1.62× speedups after the attention softmax optimization. Feedback's
qualified AMD FP32 ONNX graph measured about 2.65 seconds at 32K, with a
short-input regression relative to its previous graph. These measurements use
different models and workloads. CPU configurations can retain
`use_cpu: true`, but should keep bounded routing inputs unless their measured
latency budget permits full documents. CUDA execution paths remain available;
this release's AMD measurements do not establish NVIDIA hardware performance.
