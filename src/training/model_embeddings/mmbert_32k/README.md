# mmBERT-32K training

This package trains the three related mmBERT-32K text models used for
long-context embedding and reranking.

| Model | Entry point | Configuration | Objective |
| --- | --- | --- | --- |
| `mmbert-32k-yarn` | `foundation.py` | `configs/foundation.json` | 32K masked-language continuation with YaRN |
| `mmbert-embed-32k-2d-matryoshka` | `embedder.py` | `configs/embedder.json` | Multiple-negatives ranking with 2D Matryoshka supervision |
| `mmbert-rerank-32k-2d-matryoshka` | `reranker.py` | `configs/reranker.json` | Binary relevance loss across 20 layer/dimension heads |

The public [mmBERT-32K model guide](../../../../website/docs/training/mmbert-32k-models.md)
explains when to use each architecture. This README focuses on running the
checked training configurations.

## Reproduce Vela text checkpoints

The Vela task-weight continuation uses the run-specific `reproduction/`
package shipped with `llm-semantic-router/Vela-1.0-Encoder-307M-Embedding`
and `llm-semantic-router/Vela-1.0-Encoder-307M-Reranker`. Find each published
checkpoint and its immutable revision in the
[Vela model collection](https://huggingface.co/collections/llm-semantic-router/vela-10-router-models-6aa555ba70cc6997d6d67798).
The BGE/AllNLI configurations below are the original training entry points;
they do not reproduce the Vela MIRACL, semantic-pair, and long-context repair
mixtures.

Download the chosen checkpoint's reproduction package, using the exact
revision reported by its model card:

```bash
export VELA_MODEL=llm-semantic-router/Vela-1.0-Encoder-307M-Embedding
export VELA_REVISION="REPLACE_WITH_MODEL_CARD_COMMIT_SHA"
export VELA_SNAPSHOT=/path/to/vela-snapshot

hf download "$VELA_MODEL" --revision "$VELA_REVISION" \
  --include 'reproduction/*' --local-dir "$VELA_SNAPSHOT"
cd "$VELA_SNAPSHOT/reproduction"
python -m pip install --requirement requirements.txt
export VELA_REPRODUCTION_ROOT="$PWD/data-and-runs"
python download_inputs.py --root "$VELA_REPRODUCTION_ROOT"
python train_vela_long_repair_clean.py --help
```

Install the package's recorded PyTorch accelerator build before its Python
requirements. Follow `reproduction/README.md` for the complete initial
training, development selection, clean correction, frozen final evaluation,
and ONNX export commands. It includes pinned inputs, source hashes, actual
training arguments, and the explicit intermediate/full-layer representation
contract. The task models continue their original task weights; shared encoder
architecture does not imply descent from the newly continued Vela Base weights.

Vela native inference follows the loaded encoder dtype with inference autocast
disabled. Embedding masked mean and L2 normalization use FP32; reranker heads
also execute in FP32, including when an outer caller enables autocast. The
explicit reranker reader enforces this inference boundary while preserving
legacy behavior for checkpoints without representation metadata. Training may
use FP32 master weights with BF16 AMP, but checkpoint selection must evaluate a
separate candidate in the declared deployment precision. Historical AMP
inference results are a different arithmetic mode and must be labeled as such;
they cannot establish native or ONNX accuracy in another mode.

The Vela PAWS-X loader defaults to excluding either-sentence empty or `NS`
placeholders with `strip().casefold()`, using [pawsx_data.py](pawsx_data.py).
The clean correction records exclusion counts and asserts that sampled pairs
contain no placeholders. Archived recipes explicitly opt into historical
sampling only to reproduce their recorded runs; their existing manifests and
scores remain unchanged. Raw and cleaned PAWS-X evaluations are reported
separately, with thresholds selected on development data. The BGE/AllNLI and
BGE/Quora/FEVER loaders in this repository do not load PAWS-X, so this
dataset-specific placeholder rule is not applied to those sources.

## Train a new task from a standard Base

[`newbase_training.py`](newbase_training.py) trains the complete ModernBERT
encoder from an explicit local Hugging Face Base snapshot. It preserves the
Base's standard configuration, including its RoPE settings. An embedding task
uses masked mean pooling and normalized dimension prefixes; a reranker creates
fresh CLS scoring heads. The default `ExitSpec` supervises all 20 combinations
of layers `[3, 6, 11, 22]` and dimensions `[768, 512, 256, 128, 64]` in each
update. No previous task weights or external teacher are needed. Other exit
sets must include the encoder's full depth and width.

Prepare separate dataset directories, each containing `components.jsonl`,
`records.jsonl`, and a `manifest.json` with its `split` and both file SHA256s.
[`FrozenCorpus`](newbase_data.py) checks complete text hashes, normalized text
hashes, component references, and parent groups. Each retrieval record names a
query, all known positives, judged negatives, unjudged candidates, and its
explicit `candidate_component_ids`. Every candidate must belong to one of
those relevance partitions. Semantic-pair records instead contain two
`pair_component_ids` and a `[0,1]` label. Keep source licensing and split/group
exclusion in the data producer; loading a valid manifest does not establish
those properties.

Related, unjudged documents are masked as contrastive alternatives by default.
For a deliberately ordered pair that shares source parents, the producer can
set `contrastive_preference_component_ids` to an explicit subset of its
unjudged candidates. This enables that contrastive comparison while preserving
the unknown relevance label; it does not admit the pair to BCE or Lambda loss.

Freeze batches before training with
[`prepare_stream`](newbase_stream.py). A stream specification contains `seed`,
`cycles`, and a `sources` mapping. Each source specifies `steps_per_cycle`,
`batch_queries`, and `strata`, a mapping from stratum names to record IDs.
Sampling cycles through independent parent groups and preserves the supplied
candidate lists:

```python
from pathlib import Path
import json
from src.training.model_embeddings.mmbert_32k.newbase_data import FrozenCorpus
from src.training.model_embeddings.mmbert_32k.newbase_stream import prepare_stream

corpus = FrozenCorpus.load(Path("/data/retrieval/train"), "train")
specification = json.loads(Path("/data/retrieval/stream.json").read_text())
prepare_stream(corpus, specification, Path("/data/retrieval/draws"))
```

The training JSON uses these fields. Paths point to local files; hashes bind
the exact model, data, stream, and imported code used by the run.

| Fields | Meaning |
| --- | --- |
| `task`, `run_id`, `seed` | `embedding` or `reranker`, a run name, and initialization/RNG seed. |
| `base_directory`, `base_files` | Standard Base snapshot and relative filename-to-SHA256 mapping. |
| `train_directory`, `development_directory`, `train_manifest_sha256`, `development_manifest_sha256` | Separate training and development corpora; optional `train_split`/`development_split` default to `train`/`validation`. |
| `draws_directory`, `draws_sha256`, `steps` | Frozen stream and its exact number of optimizer updates. |
| `code_root`, `execution_lock_path`, `execution_lock_sha256` | Code snapshot and JSON `files` mapping of relative Python paths to SHA256s; every imported task module must be included. |
| `exits` | `layers`, `dimensions`, `layer_weights`, and `dimension_weights`; each weight vector sums to one. `ExitSpec().to_dict()` gives the default 20 exits. |
| `objectives` | Per-source explicit loss configurations described below. |
| `optimizer` | `warmup_steps`; optional `encoder_lr`, `head_lr`, `weight_decay`, `betas`, `eps`, and `minimum_lr_ratio` for AdamW with cosine decay. |
| `training_precision`, `gradient_checkpointing`, `gradient_clip_norm` | FP32 master weights with `float32` or `bfloat16` forward, optional non-reentrant checkpointing, and clipping norm. |
| `source_maximum_tokens`, `training_token_budget`, `evaluation_token_budget` | Per-source complete-input limit and padded microbatch budgets. Inputs are never truncated. |
| `eval_steps`, `maximum_seconds` | Evaluation steps start at zero; optional elapsed-time limit stops before the next update. A running update or evaluation may exceed that limit. |
| `evaluation`, `selection` | Optional reporting slices and numeric development selection policy. Selection also requires `baseline_path` and `baseline_sha256`. |
| `provenance`, `expected_initial_state_sha256` | Optional lineage metadata and an exact initial tensor-state check. |

Embedding objective `kind` is `retrieval`, `cosent`, or `paraphrase`. Retrieval
supports multi-positive contrastive supervision and optional
`distillation_weight` from the current, detached full exit to smaller exits.
`cosent` uses graded pair ordering; `paraphrase` uses binary labels and an
explicit margin. Reranker `kind: ranking` combines configurable
`pairwise_weight`, `bce_weight`, `preference_weight`, and `lambda_weight`.
Unjudged alternatives can contribute preference supervision, but are excluded
from BCE and LambdaLoss; `positive_bce_judged: false` also excludes an
unjudged composite positive from those absolute relevance terms. See
[`ObjectiveConfig`](newbase_batches.py) for scales, temperature, candidate
limits, and defaults. Source names do not select the loss implicitly.

Run from the repository root with an environment that supports the Base's
actual Transformers configuration and accelerator. Expose one assigned device
for GPU training. The configuration hash below is the SHA256 of the JSON file:

```bash
export PYTHONPATH="$PWD"
python -m src.training.model_embeddings.mmbert_32k.newbase_training \
  --config /data/retrieval/task.json --config-sha256 CONFIG_SHA256 \
  --output /data/retrieval/run --device cuda

python -m src.training.model_embeddings.mmbert_32k.newbase_scoring \
  --model /data/retrieval/run/step-100 --task embedding \
  --known-dev /data/retrieval/validation --split validation \
  --output /data/retrieval/evaluation --device cpu --token-budget 32768
```

Use `--task reranker` for a reranker checkpoint. Evaluation runs in FP32,
reports every configured exit, and writes aggregate `metrics.json` and numeric
per-record scores. Optional `--evaluation-config` names source/language/length
slices or semantic metrics. Selection constraints and score weights are
explicit configuration, with identical dataset support and precision required
for baseline comparisons.

Each `step-N` saves the complete updated encoder, tokenizer, exit/representation
metadata, and `newbase_checkpoint.json`. Rerankers additionally save every
head in `classification_heads.safetensors` and `matryoshka_config.json`.
`NewBaseTask.resume()` verifies hashes and reloads all exits. Training
checkpoints also preserve optimizer, scheduler, RNG, and evaluation history;
use `--resume /data/retrieval/run/step-N` with the same configuration and a new
output directory to continue the same stream. The
[two-step CPU example](tests/test_newbase_training.py) exercises a complete
configuration, training, checkpoint creation, and exact next-update resume.
Export and engine qualification remain separate from this training interface.

## Install

Use a Python environment with a compatible PyTorch build, then install the
family dependencies:

```bash
python -m pip install --requirement \
  src/training/model_embeddings/mmbert_32k/requirements.txt
```

The accelerator image and Python package versions for a release run are pinned
in `runtime.json`. Keep that environment, the resolved configuration, and
output checksums with the run.

## Configure paths

Run from the repository root and keep datasets and checkpoints outside Git:

```bash
export PYTHONPATH="$PWD/src"
export MMBERT32K_FOUNDATION_DATA=/path/to/tokenized-cc100-32k
export MMBERT32K_FOUNDATION_OUTPUT=/path/to/mmbert-32k-yarn
export MMBERT32K_BGE_DATA=/path/to/bge-m3-data
export MMBERT32K_EMBEDDER_OUTPUT=/path/to/mmbert-embed-32k-2d
export MMBERT32K_RERANKER_OUTPUT=/path/to/mmbert-rerank-32k-2d
```

All model and dataset revisions, random seeds, objectives, and production
hyperparameters live in the JSON configurations. Command-line arguments are
applied after the config and are explicit overrides.

## Inspect commands first

The family runner can resolve a command without importing the ML stack:

```bash
python -m training.model_embeddings.mmbert_32k \
  --config src/training/model_embeddings/mmbert_32k/configs/foundation.json \
  --stage prepare --print-command

python -m training.model_embeddings.mmbert_32k \
  --config src/training/model_embeddings/mmbert_32k/configs/foundation.json \
  --stage train --print-command

python -m training.model_embeddings.mmbert_32k \
  --config src/training/model_embeddings/mmbert_32k/configs/embedder.json \
  --print-command

python -m training.model_embeddings.mmbert_32k \
  --config src/training/model_embeddings/mmbert_32k/configs/reranker.json \
  --print-command
```

Remove `--print-command` to execute the selected workflow.

## Train the 32K foundation

Foundation data preparation streams the nine configured CC-100 languages,
inserts tokenizer document boundaries, and emits only complete 32,768-token
sequences. The target is 30,774 sequences: 3,420 each for `en`, `zh-Hans`, and
`de`, followed by 3,419 each for `fr`, `es`, `ru`, `ar`, `ja`, and `ko`.

Preparation uses two passes so the second pass can verify the exact compressed
source prefixes observed by the first:

```bash
export MMBERT32K_FOUNDATION_AUDIT=/path/to/mmbert32k-cc100-audit

python -m training.model_embeddings.mmbert_32k \
  --config src/training/model_embeddings/mmbert_32k/configs/foundation.json \
  --stage prepare --output_dir "$MMBERT32K_FOUNDATION_AUDIT"

python -m training.model_embeddings.mmbert_32k \
  --config src/training/model_embeddings/mmbert_32k/configs/foundation.json \
  --stage prepare \
  --source_prefix_contract_dir "$MMBERT32K_FOUNDATION_AUDIT"
```

The replay writes a packing manifest that binds source counters and hashes,
packed-token content, Arrow schema, and every shard checksum. Foundation
training validates that manifest before loading model weights:

```bash
python -m training.model_embeddings.mmbert_32k \
  --config src/training/model_embeddings/mmbert_32k/configs/foundation.json \
  --stage train
```

The training config applies official YaRN position scaling before model
construction, validates each rotary layer, uses SDPA attention, and continues
masked-language modeling for one epoch. It also flushes and correctly scales
the final partial gradient-accumulation window.

CC-100's dataset card does not declare a license and its content is derived
from Common Crawl. Preparation requires the explicit acknowledgement recorded
in the config. Review the dataset card, Common Crawl terms, privacy, and the
intended release jurisdiction before redistributing packed data or publishing
new weights.

## Train the embedder

Download the BGE-M3 training data at the revision pinned in the config, then
run:

```bash
hf download Shitao/bge-m3-data \
  --repo-type dataset \
  --revision a69db8b86e9c1767d193ee0de95e5c4001a71eae \
  --local-dir "$MMBERT32K_BGE_DATA"

python -m training.model_embeddings.mmbert_32k \
  --config src/training/model_embeddings/mmbert_32k/configs/embedder.json
```

The configuration trains normalized embeddings at dimensions 768, 512, 256,
128, and 64 and enables adaptive-layer supervision. It also includes the
pinned AllNLI training source and STS-B evaluation source.

## Train the reranker

The reranker uses the same BGE-M3 data directory:

```bash
python -m training.model_embeddings.mmbert_32k \
  --config src/training/model_embeddings/mmbert_32k/configs/reranker.json
```

The trainer creates heads at layers 3, 6, 11, and 22 for dimensions 768, 512,
256, 128, and 64. Keep `classification_heads.pt` and
`matryoshka_config.json` with the encoder and tokenizer when packaging the
artifact.

## Portable launchers

These wrappers resolve through the same configs:

```bash
bash src/training/model_embeddings/mmbert_32k/run_rope_training.sh --print-command
bash src/training/model_embeddings/mmbert_32k/run_bge_style_training.sh --print-command
bash src/training/model_embeddings/mmbert_32k/run_rerank_2d_matryoshka_training.sh --print-command
```

Set `MMBERT32K_STAGE=prepare` when using `run_rope_training.sh` for data
preparation. `MMBERT32K_PYTHON_BIN` selects a non-default Python executable.

## Validate

The lightweight contract suite does not download models:

```bash
python -m unittest discover \
  -s src/training/model_embeddings/mmbert_32k/tests \
  -p 'test_*.py'
```

Before release, evaluate the embedder at every supported dimension and selected
layer, evaluate all reranker heads, and run long-context loading and loss checks
for the foundation. Record the exact revisions, resolved config, dataset
manifest, metrics, and artifact checksums.
