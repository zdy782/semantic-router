---
title: Current Model Catalog
sidebar_label: Model Catalog
---

# Current model catalog

## Vela 1.0

Vela is the current router model family. All eleven models share the published
Vela Encoder base. Each task release contains the files needed for inference;
training and evaluation tools live in this repository.

| Model | Purpose |
| --- | --- |
| [Encoder](https://huggingface.co/llm-semantic-router/Vela-1.0-Encoder-307M) | Shared base for task adaptation |
| [Domain](https://huggingface.co/llm-semantic-router/Vela-1.0-Encoder-307M-Domain) | 14 request domains |
| [Guard](https://huggingface.co/llm-semantic-router/Vela-1.0-Encoder-307M-Guard) | Prompt injection and jailbreak attacks |
| [Safety](https://huggingface.co/llm-semantic-router/Vela-1.0-Encoder-307M-Safety) | Unsafe content |
| [Hazard](https://huggingface.co/llm-semantic-router/Vela-1.0-Encoder-307M-Hazard) | 12 independent content hazards |
| [PII](https://huggingface.co/llm-semantic-router/Vela-1.0-Encoder-307M-PII) | 17 personal-information entity types |
| [FactCheck](https://huggingface.co/llm-semantic-router/Vela-1.0-Encoder-307M-FactCheck) | Need for factual verification |
| [Feedback](https://huggingface.co/llm-semantic-router/Vela-1.0-Encoder-307M-Feedback) | Four feedback types plus NO_FEEDBACK |
| [Modality](https://huggingface.co/llm-semantic-router/Vela-1.0-Encoder-307M-Modality) | Text, image or combined output intent |
| [Embedding](https://huggingface.co/llm-semantic-router/Vela-1.0-Encoder-307M-Embedding) | Multilingual retrieval with 20 layer/dimension combinations |
| [Reranker](https://huggingface.co/llm-semantic-router/Vela-1.0-Encoder-307M-Reranker) | Pair relevance with 20 layer/dimension scoring heads |

See [Vela runtime configuration](/docs/tutorials/global/vela-models) for defaults,
input budgets, hardware and live verification. Model cards provide quickstarts
and matched comparisons with the previous mmBERT family.

## Previous mmBERT and multimodal models

The following tables preserve the earlier
[embedding](https://huggingface.co/collections/llm-semantic-router/mom-multilingual-embed)
and [classifier](https://huggingface.co/collections/llm-semantic-router/mom-multilingual-class)
collections and their original training workflows. Their base models and data
recipes describe those releases, not the current Vela training lineage.
Multimodal models remain separate from Vela 1.0.

### Earlier embedding and reranking artifacts

| Logical model | Published artifact | Architecture | Training method |
| --- | --- | --- | --- |
| mmBERT-32K foundation | [`mmbert-32k-yarn`](https://huggingface.co/llm-semantic-router/mmbert-32k-yarn) | ModernBERT masked-language encoder with a 32K YaRN context | Continued multilingual masked-language modeling |
| mmBERT-32K embedder | [`mmbert-embed-32k-2d-matryoshka`](https://huggingface.co/llm-semantic-router/mmbert-embed-32k-2d-matryoshka) | Bi-encoder with layer- and dimension-selectable embeddings | Multiple-negatives ranking with 2D Matryoshka supervision |
| mmBERT-32K reranker | [`mmbert-rerank-32k-2d-matryoshka`](https://huggingface.co/llm-semantic-router/mmbert-rerank-32k-2d-matryoshka) | Cross-encoder with 20 layer/dimension scoring heads | Binary relevance loss averaged across all heads |
| Small multimodal embedder | [`multi-modal-embed-small`](https://huggingface.co/llm-semantic-router/multi-modal-embed-small) | MiniLM, SigLIP, and Whisper-tiny towers with two-layer fusion; 384 dimensions | Staged image-text and audio-text contrastive alignment with Matryoshka loss |
| Large multimodal embedder | [`multi-modal-embed-large`](https://huggingface.co/llm-semantic-router/multi-modal-embed-large) | mmBERT-32K, SigLIP2-SO400M, and Whisper-medium tri-encoder; 768 dimensions | Cached multiple-negatives ranking with hard negatives |

See [mmBERT-32K models](./mmbert-32k-models) and
[multimodal embeddings](./multimodal-embeddings) for the data flow, objectives,
configuration, and commands.

### Earlier classifier artifacts

The first six classifiers below use the multilingual mmBERT-32K/ModernBERT
encoder. The two earlier safety artifacts use `jhu-clsp/mmBERT-base`; the
current safety workflow can train 32K successor artifacts. Sequence
classifiers predict one label for the request; the PII model predicts a BIO
label for each token.

| Logical model | Labels or output | Published artifacts | Training method |
| --- | --- | --- | --- |
| Intent classifier | 14 subject areas | [`merged`](https://huggingface.co/llm-semantic-router/mmbert32k-intent-classifier-merged), [`LoRA`](https://huggingface.co/llm-semantic-router/mmbert32k-intent-classifier-lora) | LoRA sequence classification on MMLU-Pro plus fallback-intent examples |
| Jailbreak detector | `benign`, `jailbreak` | [`merged`](https://huggingface.co/llm-semantic-router/mmbert32k-jailbreak-detector-merged), [`LoRA`](https://huggingface.co/llm-semantic-router/mmbert32k-jailbreak-detector-lora) | LoRA sequence classification on benign/toxic chat, attack data, and pattern augmentation |
| Feedback detector | Four feedback states | [`merged`](https://huggingface.co/llm-semantic-router/mmbert32k-feedback-detector-merged), [`LoRA`](https://huggingface.co/llm-semantic-router/mmbert32k-feedback-detector-lora) | Class-weighted LoRA sequence classification |
| Modality router | `AR`, `DIFFUSION`, `BOTH` | [`merged`](https://huggingface.co/llm-semantic-router/mmbert32k-modality-router-merged), [`LoRA`](https://huggingface.co/llm-semantic-router/mmbert32k-modality-router-lora) | LoRA with focal loss, class balancing, and optional synthetic mixed-modality prompts |
| Fact-check classifier | `FACT_CHECK_NEEDED`, `NO_FACT_CHECK_NEEDED` | [`merged`](https://huggingface.co/llm-semantic-router/mmbert32k-factcheck-classifier-merged), [`LoRA`](https://huggingface.co/llm-semantic-router/mmbert32k-factcheck-classifier-lora) | Balanced LoRA sequence classification on information-seeking and non-information-seeking prompts |
| PII detector | 17 entity types represented by 35 BIO labels | [`merged`](https://huggingface.co/llm-semantic-router/mmbert32k-pii-detector-merged), [`LoRA`](https://huggingface.co/llm-semantic-router/mmbert32k-pii-detector-lora) | LoRA token classification with character-offset-to-token alignment |
| Safety Level 1 | `safe`, `unsafe` | [`LoRA adapter`](https://huggingface.co/llm-semantic-router/mmbert-safety-binary-merged) | Deterministic prompt-only LoRA sequence classification |
| Safety Level 2 | Nine hazard outputs | [`LoRA`](https://huggingface.co/llm-semantic-router/mmbert-safety-binary-hazard) | Deterministic prompt-only LoRA sequence classification with a fixed taxonomy crosswalk |

See [classifier models](./classifier-models) for the first six tasks and
[safety classifiers](./mmbert-safety-classifier) for the two-level safety
pipeline.

## Choose an earlier release shape

Use a merged artifact when the runtime expects a standalone Transformers model.
Use a LoRA artifact when the runtime can load PEFT adapters and you want a
smaller task-specific artifact. Both shapes must retain the same tokenizer,
label order, base-model compatibility, and preprocessing contract used during
training.

Model cards describe the released weights. The checked-in training
configuration describes a new run. When they differ, treat the release as an
existing artifact and the in-tree configuration as the source of truth for
retraining; do not assume a new checkpoint will be bit-identical without the
original data and run receipt.

The Level 1 safety artifact is a PEFT adapter even though its historical name
ends in `-merged`. Inspect artifact contents and metadata instead of inferring
the loading method from a suffix.
