---
title: Safety models
description: Configure prompt guard, PII, and hallucination checks and choose how to handle failures.
---

Safety models detect risks; routing decisions and plugins determine the action.
Enabling a model alone does not block or redact a request.

| Check | What it detects | Configure the action |
| --- | --- | --- |
| Prompt guard | Prompt injection and jailbreaks | [Jailbreak signals](../../tutorials/signal/learned/jailbreak.md) |
| PII | Personal information in text | [PII signals](../../tutorials/signal/learned/pii.md) |
| Hallucination | Answer claims unsupported by supplied context | [Hallucination plugin](../../tutorials/plugin/hallucination.md) |
| Fact-check | Whether a request needs factual verification | [Fact-check signals](../../tutorials/signal/learned/fact-check.md) |

## Prompt guard

To enable the maintained local guard, merge this into your configuration:

```yaml
global:
  model_catalog:
    modules:
      prompt_guard:
        enabled: true
        variant: mmbert32k
        threshold: 0.7
        on_error: block
```

Then add the jailbreak signal and decision that should handle a match. To use
a separately hosted model, follow [External services](external.md).
The recipe's `prompt_guard` binding selects the model; the threshold and
routing policy remain in their existing settings.

## PII

Use a complete token-classification checkpoint with the matching PII label map.
Select it through the recipe's `pii_classifier` binding with
`contract: token_spans.v1`. Set its deployment and adapter as in
[In-process models](in-process.md), and provide the checkpoint's
`mapping_path`. The [PII guide](../../tutorials/signal/learned/pii.md) covers
entity thresholds and redaction.

External PII services must return scored entities and valid Unicode text
positions. An invalid response is an error, not an empty successful scan.

## Hallucination detection

The local detector checks an answer against its context and question. An
optional NLI explainer checks whether a premise supports a hypothesis.
Enable the maintained models with:

```yaml
global:
  model_catalog:
    modules:
      hallucination_mitigation:
        enabled: true
        detector:
          backend: candle
          model_ref: hallucination_detector
          threshold: 0.82
        explainer:
          model_ref: hallucination_explainer
          threshold: 0.9
```

These local models use Candle. A remote chat service can replace the detector;
NLI still requires a supported local explainer. Configure how context is
supplied and how detected spans are handled in the
[hallucination guide](../../tutorials/plugin/hallucination.md).

### Content safety and prompt attacks

Use `routing.signals.safety` for content risks and `routing.signals.jailbreak`
for prompt injection, jailbreak and instruction hijacking. A harmful request
can contain no prompt attack, and an instruction hijack can ask for otherwise
harmless output.

The [Safety signal guide](../../tutorials/signal/learned/safety.md) covers two complementary
heads: **Safety** predicts `safe`/`unsafe`; **Hazard** predicts independent risk
categories. A category-specific rule first requires the Safety score to reach
its threshold, then checks whether any selected Hazard category reaches its
own threshold. The router skips Hazard inference when Safety is below threshold.

Omit a rule's `model` to use the native head configured under
`global.model_catalog.modules.safety`. Set `model` to an external classifier
name to use `POST /classify` instead. Native heads are independently owned by
the recipe, shared between its identical rule contracts, and released when the
recipe closes. Local artifact labels and activation are checked on loading.
External endpoints must return the complete declared label set. Safety scores
form a softmax distribution; Hazard scores are independent sigmoid values and
may sum to more than one.

The [content-safety fragment](https://github.com/vllm-project/semantic-router/blob/main/config/fragments/signal/safety/content-safety.yaml)
shows two HTTP heads with a privacy-specific policy and a general unsafe policy.
Replace `default-model` with a safety-capable provider alias and configure the endpoint addresses.
Thresholds are examples, not universal calibration. `rules.on_unknown:
fail_request` returns HTTP 503 when a required classification fails. A known
unsafe result selects the configured policy: the example refuses unsafe privacy
abuse and routes other risks to the backend. General content risk can include a
person in crisis who needs a supportive response, so it should not automatically
trigger a blanket refusal.

### Native classifier context

`max_sequence_length` on the domain, PII, prompt-guard, feedback, fact-check and
modality classifier modules is an explicit native mmBERT input budget. Zero
retains the historical 512-token budget. Larger values must fit the loaded
artifact's position capacity. Configure the separate Safety/Hazard head budgets
under `modules.safety.safety` and `modules.safety.hazard`.

For the supported local classifier paths, a budget above 512 also enables full
routing text instead of representative sampling or small security windows.
Over-budget inputs produce an inference error rather than a result computed
from an unseen truncation. Existing PII/jailbreak configurations with the
historical budget retain overlapping scans across the entire input. Choose a
budget supported by task-level quality and latency measurements; positional
capacity alone is not evidence of long-text accuracy.

For native mmBERT embedding signals, set
`global.model_catalog.embeddings.semantic.embedding_config.full_context: true`
to use the loaded embedding model's complete context capacity. The default
keeps representative routing samples for latency. This affects the embedding
signal; unrelated semantic consumers keep their own policies.

## Handle failures and missing scores

A model error produces an unknown result. The decision's `rules.on_unknown`
chooses `no_match`, `match`, or `fail_request`. Without that setting, prompt
guard uses `on_error`: `allow` means no match, while `block` means a policy match.
The consuming decision still determines the resulting action.

A chat verdict or policy fallback may have no confidence score. Diagnostics
show `confidence: null` with `confidence_available: false`; this is different
from a model score of zero. Test both model matches and service failures when
setting the policy.

For custom safety checkpoints, see the
[training and export guide](../../training/mmbert-safety-classifier.md).

For access control and rate limits, see [Security hardening](../security-hardening.md).
