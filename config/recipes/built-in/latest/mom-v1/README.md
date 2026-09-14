# MoM V1 Model Card

## Overview

Five ways to route a mixed workload. Choose a goal, connect your models, and
publish one API entrypoint.

| Recipe | Goal | Decisions |
| --- | --- | --- |
| **Balance** | Everyday quality, responsiveness, and cost | `simple`, `medium`, `reasoning` |
| **Speed** | Fast interaction and efficient streaming | `fast`, `tools`, `reasoning` |
| **Cost** | Lower serving cost with targeted escalation | `economy`, `tools`, `reasoning` |
| **Accuracy** | Strong answers and deliberate use of multiple models | `simple`, `reasoning`, `review`, `agent` |
| **Vault** | Private processing within your assigned deployment boundary | `private`, `sensitive`, `guard` |

## Model details

MoM V1 is a family of routing policies. Policy version **3.0** uses the compact
decision names above and keeps the existing public model IDs. Its recipes ship
with vLLM Semantic Router; you supply the generation backends. Embedding and
complexity rules use rule-level settings to keep all declared candidate texts
for scoring instead of compressing them to a global bank limit.

## Intended use

Use Balance for mixed workloads, Speed for interactive applications, Cost for
cost-sensitive serving, Accuracy for demanding work, and Vault for an approved
private deployment. Each recipe can use a different set of connected models.

## Routing behavior

**Balance** uses an efficient pool for clearly simple work, a stronger reasoning
pool for hard tasks or answer recovery, and a balanced pool in between. Domain
and FactCheck signals help identify consequential advice; a medical definition
alone does not require escalation.

**Speed** favors first-token latency for ordinary conversation and tools, and
per-token latency for reasoning. Lightweight semantic and request-shape signals
keep routing overhead small.

**Cost** keeps requests on one model. Its base selector prefers the lowest
estimated request cost within the decision's quality band, with stronger pools
for reasoning and active tool use. After an assistant answer, correctness
feedback can escalate answer recovery; repetition or a formatting edit alone
does not establish that the answer was wrong.

**Accuracy** normally uses one strong model. An explicit request for independent
review selects `review`, which compares two responses and synthesizes them.
An explicit request to delegate work to multiple workers selects `agent`, with
at most three steps and two workers in parallel. The router plans the internal
stages and combines results; users need not name those stages. Describing,
translating, or prohibiting a workflow does not authorize execution. Long context or a subject label does not trigger fan-out.
A client-owned tool loop stays on the single-model reasoning path.

**Vault** uses separate pools for ordinary and sensitive requests. `guard`
contains detected prompt attacks before calling a backend. Safety and Hazard
route content risks to `sensitive`, where the assigned model can provide help,
explain risky material, or refuse harmful assistance. Hazard uses its published
per-category operating point independently of the binary Safety verdict.

Router Learning can adapt single-model choices from real outcomes within the
matched decision's eligible pool. Preview reports `execution_required` when
adaptation determines the final choice during execution. Conversation protection
can keep an eligible model across turns when clients send stable session and
conversation identities. Vault and multi-model execution bypass automatic
adaptation.

## Requirements

Assign at least one qualified model to each single-model decision and at least
two distinct worker models to Accuracy's `review` and `agent`. Vault's `guard`
responds immediately and needs no model assignment.

Models must declare their capabilities, context window, and maximum output
limit. Images and long inputs use the same decisions as other work; candidate
checks enforce their requirements. Missing metadata or an insufficient eligible
pool produces an explicit error.

Single-model decisions compare the catalog's versioned `general`, `reasoning`,
or `agentic` quality index at the assigned reasoning effort. Custom models need
relevant benchmark evidence. Cost comparisons require comparable configured
prices; latency comparisons use observations from real requests.

Absent client output limits default to 4,096 tokens, or 8,192 for reasoning and
Accuracy's single-model answers. Explicit limits are preserved. Multi-model
calls use declared stage budgets and are checked again before dispatch.

Vault uses the default logical `hazard` deployment for its category classifier.
It loads only when used. Override that deployment for qualified accelerator
execution while retaining the model's `operating_point.json`. Verify the sensitive
pool on help-seeking, benign analysis, and harmful requests; a general quality
score does not certify responsible answers.

## Data handling and safety

Every Vault path disables client tools, strips tool history, and disables Router
memory, response caching, replay capture, and learning adaptation. It also
suppresses new Responses object writes. These restrictions apply regardless of
the Guard, Safety, Hazard, and PII verdicts; unavailable triage fails closed.

Assign every Vault backend to infrastructure that meets your privacy
requirements. The recipe does not establish physical placement, change provider
retention, delete earlier stored conversations, or disable operational usage
metadata.

## Quick start

```bash
vllm-sr serve
```

Connect models in the Dashboard, choose a recipe, assign its decision pools,
and publish an entrypoint. Use **Preview** to inspect signals, decisions, and
candidate selection. Then send a real request through the entrypoint to verify
backend execution and latency.

When upgrading to policy 3.0, verify sensitive-content delivery: content risk
now selects a responsible private model instead of a fixed denial. Prompt
attacks still receive an immediate response. Existing published versions and
their assignments remain unchanged.

## Evaluation

[`probes.yaml`](probes.yaml) covers multilingual requests, negative examples,
priority collisions, tools, images, retained conversation, and long inputs.
Validate routing behavior and actual backend eligibility against your deployment;
a correct decision alone does not prove that an assigned model can serve it.
See the [conformance guide](../../../CONFORMANCE.md) for commands.

## Limitations

Quality bands compare the assigned pool; they do not guarantee answer accuracy.
Context accounting includes conversation history and output reserves but remains
an estimate rather than a provider-tokenizer guarantee. Learned signals can
misclassify requests, so validate representative traffic before rollout.

Knowledge-base retrieval, reranking, caching, and memory can be added for
applications that need them. These reusable recipes require no knowledge base
and inject no system prompt. Use [recipe tuning](https://vllm-sr.ai/docs/benchmarking/agent-evaluation-loop)
to measure these additions and session continuity against real requests.

## References

[Documentation](https://vllm-sr.ai/) ·
[GitHub](https://github.com/vllm-project/semantic-router) ·
[Recipe conformance](../../../CONFORMANCE.md)
