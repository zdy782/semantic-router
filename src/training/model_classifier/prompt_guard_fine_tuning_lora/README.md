# Vela Guard

Vela detects prompt injection and jailbreak attempts independently of content
safety. The current licensed-source builders are `vela_data.py` and
`vela_authored.py`; training uses the explicit shared sequence loop. See the
[Vela application recipes](../vela-applications.md) for output contracts,
fixed sources, initialization, long-context evaluation and export.

For reviewed source-boundary contrasts, run
`python -m src.training.model_classifier.prompt_guard_fine_tuning_lora.vela_source_boundary
--config reviewed-families.json --output contrasts/`. Supply the reviewed family
definitions explicitly and retain them with the dataset release. The builder
keeps ordinary requests, attacks, quotations and translations in their declared
family partition. Training corpora and historical review snapshots are separate
from the source checkout.

## Train from Vela Base

Use the [shared sequence trainer](../sequence_repair/README.md) with a fresh
complete classification head and the explicit `benign=0`, `jailbreak=1` label
contract. The base identity and immutable revision are required:

```bash
python -m src.training.model_classifier.sequence_repair.train \
  --base artifacts/vela/base \
  --base-id llm-semantic-router/Vela-1.0-Encoder-307M \
  --base-revision ccd22e6ba42f86681578229f9dfd468295da3def \
  --method full --fresh-head \
  --contract artifacts/vela/guard/contract.json \
  --train artifacts/vela/guard/train.jsonl \
  --dev artifacts/vela/guard/dev.jsonl \
  --output artifacts/vela/guard/run --steps 600
```

Choose the training budget and development criteria before the run. `benign`
means no instruction attack, not that the requested content is safe. Include
harmful requests without attacks, harmless instruction attacks, and quoted or
negated attacks in the appropriate task partitions. Do not use toxicity labels
as prompt-attack labels. ToxicChat's noncommercial data is excluded from Vela
training.

Freeze the candidate using development data before final evaluation. Measure
attack recall, benign false positives, source and language coverage, and actual
context lengths. Position capacity alone does not establish task accuracy.
Regenerate inference graphs from each selected checkpoint's actual weights.

The legacy `jailbreak_bert_finetuning_lora.py` interface remains available only
for explicit checkpoint inference and adapter export compatibility. Historical
training code and fixed candidate corpora are not Vela training entrypoints.
