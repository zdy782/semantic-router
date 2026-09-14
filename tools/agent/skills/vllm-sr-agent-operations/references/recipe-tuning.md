# Tune routing from application examples

Use this reference after discovering the running schema and selecting the
deployment through the [operations skill](../SKILL.md). Start with an application
objective: better answers, faster responses, lower cost, safer handling, or more
stable agent runs. Record the acceptable tradeoffs before changing a threshold.

## Map the complete path

Inspect every entrypoint, including its named Recipe and model assignments.
Write down what each part contributes:

| Part | Design question |
| --- | --- |
| Signals | What evidence distinguishes requests that need different handling? |
| Projections | Which combinations, scores, or partitions summarize that evidence? |
| Decisions | Which distinct actions does the application need? |
| Algorithms | How does each action select or coordinate eligible models? |
| Plugins | What retrieval, tool, cache, or privacy behavior belongs to that action? |
| Models | Can the assigned endpoints execute the actual request and output budget? |

Prefer a few decisions with short names. Keep `simple`, `medium`, and `reasoning`
distinct because their service objectives differ; do not create one decision
per keyword, language, or classifier label. A fallback should also have an
explicit quality and availability policy.

## Select evidence for a purpose

Use heuristics for protocol facts and explicit constraints: active tool calls,
required tool choice, structured output, or a declared privacy requirement.
Use Embedding for semantic intent, Complexity for effort, Domain with FactCheck
for consequential questions, and Feedback with Reask for recovery. Topic alone
does not establish difficulty; FactCheck predicts a need for checking and does
not verify a statement.

Combine independent clues in a projection when no single clue is sufficient.
Review negative conditions and `on_unknown` together: an inference failure must
not become an ordinary false value under `NOT`. Include failing-model tests.
Do not assume an early keyword condition avoids learned inference. Used signal
families can execute concurrently before decision composition; measure the
whole request and the actual forwards.

Guard detects prompt attacks. Safety and Hazard identify content risk and
categories; they do not establish malicious intent. Pair harmful requests with
help-seeking, quotation, and analysis controls before choosing refusal behavior.
PII can select a restricted processing pool, but it does not redact content or
establish where a provider stores it.

## Add retrieval where evidence is available

Use Rerank after retrieval from a real knowledge base. Start with a single-model
answer path, retrieve a wider candidate set, and retain a smaller ranked set
through `rag.rerank`. Verify its recipe-scoped `rag.reranker` binding. Preserve
document identities and assess retrieved coverage, ranking, grounded answer
quality, and added latency separately.

Preview verifies selection of the RAG plugin; a routed request verifies retrieval
and reranking. A relevance score is not a truth probability. Avoid attaching RAG
to every multi-model stage without checking repeated retrieval and context growth.
Keep the ordinary no-KB path usable without provisioning a knowledge base.

## Protect agent continuity

Inspect `global.router.learning.protection` and decision-local `adaptations`;
the legacy `algorithm.type: session_aware` is not the current contract. Use stable
session and conversation identities in actual routed requests. Test a complete
tool cycle, continuation, explicit correction, failed model, decision change,
and a new conversation. Repeat the same session ID across different Recipes to
verify isolation.

Compare `apply`, `observe`, and `bypass`. An observed recommendation to stay is
not an applied hold. Verify the actual selected model, backend response, route
headers, Replay API, and Dashboard agree. Continuity cannot retain a model that
is outside the current eligible pool. Keep hard privacy boundaries and bounded
multi-model workflows explicit rather than enabling a global hold indiscriminately.

## Run a comparable experiment

1. Freeze the baseline config, assignments, runtime and model revisions. Save
   original probe identities. Add new counterexamples in a separately identified
   packet before seeing candidate outputs; keep routing controls out of training.
2. Cover every decision and fallback with ordinary, boundary, negative, multilingual,
   long-input and multi-turn cases. Include instructions quoted as data, absent
   history, required tools, unknown signals, and insufficient backend capacity.
3. Validate and activate the candidate through the
   [configuration workflow](configuration-loop.md). Verify its active revision.
4. Run real Preview requests with full messages, tools, padding and images. In the
   contributor conformance harness, choose `deployment` or `policy` scope explicitly.
   Keep strict deployment checks as the default. Report selected, immediate-response,
   execution-required and unavailable outcomes separately. Policy coverage does not
   prove backend capacity; signal errors and failed HTTP calls remain failures.
5. Send real routed requests for each execution path. Verify completed output,
   distinct workers for multi-model algorithms, plugin effects and session behavior.
6. Compare paired route outcomes and answer quality alongside cold/warm latency,
   median/p95, classifier work, backend calls, tokens and measured cost. Report
   unavailable measurements explicitly. Do not sum concurrent signal times as
   though all forwards were sequential.
7. Keep the candidate only when the stated objective and hard constraints pass.
   Otherwise restore the baseline and preserve the failed evidence. Keep raw test
   outputs outside Git; publish intentional recipes, documentation and code fixes.

Use the [evaluation loop](evaluation-loop.md) for exact Preview, Probe, delivery
and benchmark contracts. A partial benchmark can guide tuning, but it does not
establish a full leaderboard score or performance on untested hardware.
