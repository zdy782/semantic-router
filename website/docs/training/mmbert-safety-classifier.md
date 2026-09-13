---
title: Train Vela Safety and Hazard
sidebar_label: Safety Classifiers
---

# Train Vela Safety and Hazard

Vela separates content safety from prompt attacks. **Safety** predicts whether
content is safe or unsafe. **Hazard** identifies the types of content risk.
**Guard** detects prompt injection and jailbreak instructions. A harmful request
can contain no prompt attack; a prompt attack can request harmless output.

This guide covers training and exporting compatible Safety and Hazard models.
Their Vela release qualification is ongoing. The commands below describe the
supported workflow, not a claim that an arbitrary training run is ready to serve.
For deployment, use the [Safety signal guide](../tutorials/signal/learned/safety.md).

## Prerequisites

Use an isolated training environment with a platform-appropriate PyTorch build.
The reference environment uses PyTorch 2.10, Transformers 4.57.6, datasets 4.1.1,
and scikit-learn 1.7.2. LoRA additionally requires PEFT 0.18.1. Record the actual
versions and accelerator build for each run. ROCm training uses PyTorch's `cuda`
device API; installing a CUDA wheel does not provide AMD support.

Before starting, prepare:

- A downloaded encoder checkpoint and its exact repository revision.
- A task contract specifying labels, problem type, and pooling.
- Separate training, development, and final evaluation files with stable source
  IDs, source groups, and text hashes.
- A written sampling recipe, training budget, and development acceptance criteria.

Use the checkpoint's actual training parent. Attaching an old adapter to a new
encoder does not establish that the task was trained on that encoder.

## Model and label contracts

Both tasks use standard `ModernBertForSequenceClassification` checkpoints.
Safety uses `single_label_classification`; Hazard uses
`multi_label_classification`. Preserve inverse `label2id` and `id2label` maps
and the pooling mode used during training.

| Model | Labels | Output and objective |
| --- | --- | --- |
| Safety | `safe`, `unsafe` | Two-class softmax; cross-entropy |
| Hazard | The ordered categories below | Independent sigmoid; masked binary cross-entropy |

Hazard's output order is:

| ID | Category |
| --- | --- |
| 0 | `violence` |
| 1 | `criminal_activity` |
| 2 | `sexual_content` |
| 3 | `child_exploitation` |
| 4 | `hate` |
| 5 | `harassment_abuse` |
| 6 | `regulated_substances` |
| 7 | `weapons` |
| 8 | `self_harm` |
| 9 | `privacy` |
| 10 | `specialized_advice` |
| 11 | `misinformation` |

Hazard includes safe negatives and can predict multiple categories or none.
An unannotated category is unknown, not a negative label: its `label_mask` entry
must be zero. The mask removes that label's loss. Keep semantic category
judgments distinct from weak mappings of another dataset's taxonomy.

## Prepare and inspect data

The [Vela application recipes](https://github.com/vllm-project/semantic-router/blob/main/src/training/model_classifier/vela-applications.md)
describe pinned AEGIS and CultureGuard sources, source crosswalks, reviewed
supervision, boundary contrasts, and long-context construction. Source labels
can refer to an entire dialogue or a sensitive topic, so a crosswalk is not
independent evidence that the visible input violates the Vela rubric.

Keep article, conversation, translation, and paired-example families together.
Check IDs, normalized duplicates, and text containment before training. Remove
contaminated training groups while preserving held-out evaluation. Record
removals and the final source proportions. Report authored stress tests and
weakly supervised data separately from natural, independently judged examples.

Include safe discussions of sensitive topics, quoted attacks, benign
instructions, and cases requiring supportive handling. Safety and Guard need
distinct labels for these boundaries. Inspect source and category exposure:
balanced sampling can repeatedly draw a small authored set without adding
coverage.

## Train the complete encoder

The single-GPU trainers support full parameter training and LoRA continuation.
Full training starts from a complete checkpoint. `--fresh-head` initializes its
task head while preserving the encoder; omit it only for deliberate continuation
of a compatible trained head. These example paths assume each task's recipe has
already materialized `contract.json`, `train.jsonl`, and `dev.jsonl`.

Set `VELA_BASE_REVISION` to the exact downloaded parent revision before running:

```bash
python -m src.training.model_classifier.sequence_repair.train \
  --method full --fresh-head \
  --base /models/vela-base --base-id llm-semantic-router/Vela-1.0-Encoder-307M \
  --base-revision "${VELA_BASE_REVISION:?Set the downloaded parent revision}" \
  --contract /artifacts/safety/contract.json \
  --train /artifacts/safety/train.jsonl --dev /artifacts/safety/dev.jsonl \
  --output /artifacts/runs/safety \
  --steps 600 --batch-size 4 --accumulate 4 \
  --max-length 32768 --microbatch-token-budget 32768 \
  --learning-rate 0.00001 --head-learning-rate 0.0001 \
  --eval-every 200 --evaluation-dtype float32 \
  --selection binary-fp-budget-recall --positive-label unsafe \
  --selection-false-positive-budget 0.1
```

Use the dedicated multi-label trainer for Hazard:

```bash
python -m src.training.model_classifier.safety_classifier.train_vela_hazard \
  --method full --fresh-head \
  --base /models/vela-base --base-id llm-semantic-router/Vela-1.0-Encoder-307M \
  --base-revision "${VELA_BASE_REVISION:?Set the downloaded parent revision}" \
  --contract /artifacts/hazard/contract.json \
  --train /artifacts/hazard/train.jsonl --dev /artifacts/hazard/dev.jsonl \
  --output /artifacts/runs/hazard \
  --steps 600 --batch-size 4 --accumulate 4 \
  --max-length 32768 --microbatch-token-budget 32768 \
  --learning-rate 0.00001 --head-learning-rate 0.0001 \
  --eval-every 200 --evaluation-dtype float32 \
  --selection fp-budget-macro-f1 --selection-false-positive-budget 0.05 \
  --supervision-diagnostics
```

The step counts, learning rates, and false-positive budgets are examples.
Choose them for the actual data and application before comparing candidates.
Full runs save `best-model` and `last-model`, including the encoder, head, and
training origin. LoRA runs use `--method lora --adapter /path/to/initial-adapter`
and save adapter checkpoints instead; do not combine `--adapter` with full mode.

Both loops use FP32 parameters and losses with BF16 autocast. A separate head
learning rate shares the encoder's schedule. Token-budget microbatches bound
padded input size while retaining each example's weight in the complete
optimizer batch. Source and length balancing are explicit recipe choices;
inspect the recorded draws, unique examples, and label exposures.

## Evaluate accuracy and long context

Select checkpoints and thresholds using development data only. For Safety,
report unsafe recall, safe-input false positives, and per-source macro F1. For
Hazard, report supported-category precision/recall and average precision,
unknown-label coverage, and the fraction of safe inputs triggering any category.
A high average precision does not establish an acceptable false-positive rate
at the serving threshold.

The trainers do not impose a 512-token ceiling. `--max-length` must fit the
actual checkpoint capacity, and budgets include special tokens. Oversize
training examples are recorded as rejected; evaluation rejects overflow.
Inspect those counts and resolve unintended exclusions before accepting a run.

Evaluate short-input retention and actual 8K, 16K, and 32K inputs, including
signals at different positions and instructions separated from their context.
Keep natural documents distinct from constructed stress cases. Full-context
and windowed inference are different policies and need separate thresholds,
accuracy results, and latency measurements. A larger position limit alone does
not establish better long-context understanding.

## Export the selected model

Freeze the selected checkpoint before independent final evaluation. For a full
Hazard checkpoint, export with its original training parent and run receipt:

```bash
python -m src.training.model_classifier.sequence_repair.export \
  --method full --runtime-task hazard \
  --base /artifacts/runs/hazard/best-model \
  --base-id llm-semantic-router/Vela-1.0-Encoder-307M \
  --base-revision "${VELA_BASE_REVISION:?Set the downloaded parent revision}" \
  --contract /artifacts/hazard/contract.json \
  --run-manifest /artifacts/runs/hazard/run.json \
  --output /artifacts/frozen/hazard

python -m src.training.model_classifier.safety_classifier.vela_hazard \
  --base /artifacts/frozen/hazard --contract /artifacts/hazard/contract.json \
  --data /artifacts/hazard/test.jsonl --dtype float32 --max-length 32768 \
  --thresholds /artifacts/hazard/frozen-thresholds.json \
  --output /artifacts/evaluation/hazard-final.json
```

Create the threshold file from development results before final inference;
follow the [threshold evaluation contract](https://github.com/vllm-project/semantic-router/blob/main/src/training/model_classifier/vela-applications.md#freeze-evaluate-and-export).
For Safety, use `--runtime-task safety` when exporting and the shared
`sequence_repair.evaluate` command for complete class probabilities.

Export checks every saved tensor, the trained task contract, and identical FP32
logits after reload. LoRA export additionally verifies the merge. It writes
standard safetensors weights and runtime label mappings; it does not run final
evaluation or publish to Hugging Face.

## Validate the serving path

Use [in-process model bindings](/docs/installation/runtime/in-process) to select
the artifact, provider, and input policy. CPU and CUDA paths use supported native
bindings; AMD acceleration requires a compatible ROCm serving build and a
qualified ONNX graph/provider. Export new graphs whenever weights change and
verify the provider actually used, numerical parity, memory, and request latency.
Results on one accelerator do not qualify another.

The router's category-specific Safety rule runs the binary head first and
checks Hazard only when the Safety threshold passes. Hazard itself still has
an unconditional multi-label training contract. Add a decision consuming the
signal to apply a routing action; enabling a model alone does not block traffic.
Use [runtime diagnostics](/docs/installation/runtime/lifecycle-diagnostics) to
inspect real signal scores and latency through route preview.

## Reproduce legacy models

The historical workflow keeps its two-class Safety and nine-way single-label
Hazard contracts, 512-token recipe, and adapter export commands under
[safety_classifier](https://github.com/vllm-project/semantic-router/tree/main/src/training/model_classifier/safety_classifier).
Those artifacts and the `legacy-9-v1` label order remain compatibility assets.
They are separate from Vela's twelve independent Hazard outputs; changing a
label map cannot convert one into the other.
