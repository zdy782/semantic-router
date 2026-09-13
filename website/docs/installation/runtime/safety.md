---
title: Safety models
description: Configure Guard, content Safety and Hazard, PII, and grounding checks with explicit input and failure policies.
---

Safety models detect risks; routing decisions and plugins determine the action.
Enabling a model alone does not block or redact a request.

| Check | What it detects | Configure the action |
| --- | --- | --- |
| Guard | Prompt injection and jailbreaks | [Jailbreak signals](../../tutorials/signal/learned/jailbreak.md) |
| PII | Personal information in text | [PII signals](../../tutorials/signal/learned/pii.md) |
| Hallucination | Answer claims unsupported by supplied context | [Hallucination plugin](../../tutorials/plugin/hallucination.md) |
| Fact-check | Whether answering requires external factual knowledge or checking | [Fact-check signals](../../tutorials/signal/learned/fact-check.md) |

## Guard

Guard detects prompt attacks. The configuration names `prompt_guard` and
`jailbreak` remain unchanged. To enable the currently configured local guard,
merge this into your configuration:

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

## Content safety and prompt attacks

Use `routing.signals.safety` for content risks and `routing.signals.jailbreak`
for prompt injection, jailbreak and instruction hijacking. A harmful request
can contain no prompt attack, and an instruction hijack can ask for otherwise
harmless output.

The [Safety signal guide](../../tutorials/signal/learned/safety.md) covers two complementary
heads: **Safety** predicts `safe`/`unsafe`; **Hazard** predicts independent risk
categories. A category-specific rule first requires the Safety score to reach
its threshold, then checks whether any selected Hazard category reaches its
own threshold. The router skips Hazard inference when Safety is below threshold.

Omit a rule's `model` to use its recipe binding, or the native head configured
under `global.model_catalog.modules.safety` when no binding is present. Set
`model` to an external classifier name to use `POST /classify` instead. Bindings
are recipe-scoped and use the shared model lifecycle; local artifact labels,
activation and input capacity are checked on loading.
External endpoints must return the complete declared label set. Safety scores
form a softmax distribution; Hazard scores are independent sigmoid values and
may sum to more than one.

For a custom two-head deployment, merge this fragment into an existing recipe.
Supply complete checkpoints and use the Hazard labels in their trained order.
These examples require your own compatible artifacts. Vela Guard, Safety and
Hazard release qualification is ongoing.

```yaml
routing:
  model_bindings:
    safety.content-risk:
      deployment: content-safety
      contract: label_distribution.v1
      adapter: modernbert
    safety.content-risk.hazard:
      deployment: content-hazard
      contract: label_scores.v1
      adapter: modernbert
  signals:
    safety:
      - name: content-risk
        threshold: 0.7
        hazard:
          labels: [violence, criminal_activity, sexual_content, child_exploitation, hate, harassment_abuse, regulated_substances, weapons, self_harm, privacy, specialized_advice, misinformation]
          categories: [privacy]
          threshold: 0.7
global:
  model_catalog:
    deployments:
      content-safety:
        artifact: models/content-safety
        provider: candle
        device: cpu
        input: {max_tokens: 512, overflow: reject}
      content-hazard:
        artifact: models/content-hazard
        provider: candle
        device: cpu
        input: {max_tokens: 512, overflow: reject}
```

Add a decision consuming `type: safety`, `name: content-risk` to apply the
policy. The default Safety labels are `[safe, unsafe]`; Hazard requires its
complete label set and a nonempty subset of categories. Do not apply softmax
to Hazard outputs or sum independent category scores as probability mass.

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

An explicit recipe binding uses its deployment's `input.max_tokens`. Without
that binding, native classifier modules use `max_sequence_length`; omission or
zero preserves the 512-token default. The actual checkpoint and graph must
support the chosen limit. Safety and Hazard have separate module settings
under `modules.safety.safety` and `modules.safety.hazard`.

For supported local classifier signals, an explicit budget above 512 also
selects full routing text rather than representative sampling or the existing
small security scans. With the historical budget, PII and jailbreak signals
retain their overlapping scans. A 32K limit is a capacity choice, not evidence
of accuracy across a 32K document.

A Guard evaluated with token windows can use a separate whole-input budget
and inference-window size:

```yaml
routing:
  model_bindings:
    prompt_guard:
      deployment: guard-windowed
      contract: label_distribution.v1
      adapter: modernbert
      mapping_path: models/guard/jailbreak_type_mapping.json
global:
  model_catalog:
    modules:
      prompt_guard:
        enabled: true
        positive_labels: [jailbreak]
        threshold: 0.7
        on_error: block
        window: {size: 2048, overlap: 256}
    deployments:
      guard-windowed:
        artifact: models/guard
        provider: candle
        device: cpu
        input: {max_tokens: 32768, overflow: reject}
```

Replace the mapping and positive labels with the checkpoint's own values.
The total budget includes special tokens; each window's `size` also includes
special tokens, while `overlap` counts content tokens. Native inference uses
the original token IDs and preserves every window's complete output and
content-token range. Guard keeps the distribution from the window with the
highest combined positive-label probability. It does not combine per-class
maxima from different windows.

Safety and Hazard can likewise set `window` under their respective module
settings. Safety sums its selected unsafe labels within each window, then
uses the maximum window score. Hazard uses the maximum selected category
score across windows, after Safety passes its gate. Window size, thresholds
and whole-input budget must be evaluated together; remote HTTP heads cannot
use this local-tokenizer policy.

For embedding signals, see [embedding input policy](embeddings.md#input-policy).

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
