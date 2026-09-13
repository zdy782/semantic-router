---
title: Operations and troubleshooting
description: Check readiness, limit model concurrency, and update running models.
---

Use these checks after configuring an [in-process model](in-process.md) or
[external service](external.md).

## Check startup

```bash
vllm-sr config validate --config config.yaml
vllm-sr serve --config config.yaml
curl -fsS http://localhost:8080/startup-status
```

Validation checks the configuration. Startup then loads or connects the models
and checks the capabilities needed by enabled features. GPU kernel compilation
can make the first startup slower than later requests.

For local Docker deployments, `vllm-sr serve --startup-timeout 7200` allows
up to 7200 seconds for readiness after containers start. The default is
1800 seconds; the option accepts a positive integer. Select a budget using
measured startup time for the configured models, input limits, and hardware.
The CLI bounds each readiness check within that budget and allows up to five
additional seconds to collect diagnostic logs after a timeout. A timeout
leaves containers available for inspection; it does not cancel model loading
or change request inference deadlines. Check `vllm-sr status` and
`vllm-sr logs router` before deciding whether to stop the stack.

| Problem | What to check |
| --- | --- |
| Model cannot load | Complete checkpoint or ONNX files, tokenizer, labels, and mounted paths |
| Engine or device unavailable | Image and host match the selected CPU/GPU runtime |
| Label mismatch | Checkpoint label order and the rule's labels or mapping file |
| Unsupported embedding layer or dimension | Export the requested layer and match the consumer or stored index |
| Remote inference fails | Endpoint, credentials, timeout, response format, and response-size limit |
| Confidence is `null` | The result has no model score; see [Safety models](safety.md#handle-failures-and-missing-scores) |

## AMD startup problems

Select the execution provider explicitly: `rocm:N` uses the ROCm provider;
`migraphx:N` uses MIGraphX. Use an image containing that provider and the
libraries required by the graph. A CK graph also requires the trusted
`ck_flash_attention` custom-op profile. Its library identity is checked when
the session is prepared; a configuration name alone is not execution evidence.

For the maintained MIGraphX image, keep
`MIGRAPHX_MLIR_USE_SPECIFIC_OPS=~attention`; it disables MLIR attention fusion.

| Error or symptom | Action |
| --- | --- |
| Unsupported graph operator | Check the selected graph against the selected execution provider; an export for another engine is not interchangeable |
| Missing GPU embedding budget | Set a positive deployment `input.max_tokens`; see [Embeddings](embeddings.md#amd-gpu) |
| Model fails during GPU preparation | Check the graph and vendor libraries; requested GPU execution does not fall back to CPU |
| Unexpectedly slow first startup | Allow time for compilation and warmup of every requested embedding layer |

For MIGraphX, unset these process variables and configure precision in the
deployment instead:

```text
ORT_MIGRAPHX_FP16_ENABLE
ORT_MIGRAPHX_BF16_ENABLE
ORT_MIGRAPHX_FP8_ENABLE
ORT_MIGRAPHX_INT8_ENABLE
ORT_MIGRAPHX_MODEL_CACHE_PATH
```

Any nonempty value, including `0`, is rejected because it can override the
configured precision or compiled model. The maintained images leave them unset.

## Inspect the executed path

Use `POST /api/v1/routing/preview?trace=true` with the request and recipe you
intend to route. Preview runs the configured routing signals and reports their
matches, values, errors and route trace without calling a generation backend.
It does not execute the RAG retrieval/reranking plugin. Check the
[API reference](../../api/apiserver.md) for its request format.

Use startup and model-runtime observations to confirm the actual provider,
precision and effective input limits. A requested AMD device alone does not
prove GPU execution. The native ORT path rejects CPU fallback for a requested
GPU session. Preserve that distinction when comparing CPU, ROCm and CUDA.

For a live RAG request, inference spans record `rag.rerank_latency_seconds`,
`rag.rerank_candidates`, `rag.reranker_identity` and raw relevance scores.
Cached context does not represent a new reranker forward pass. Report model
inference, queue time, retrieval and backend generation separately; preview
latency is not end-to-end response latency.

## Limit concurrent inference

For the `email-risk-cpu` deployment in [In-process models](in-process.md),
this allows two calls and a queue of eight, with a one-second queue timeout:

```yaml
global:
  model_catalog:
    admission:
      email-risk-cpu:
        max_concurrency: 2
        max_queue: 8
        queue_timeout_ms: 1000
        on_overflow: shed
```

`shed` rejects excess work, `wait` waits for a queue slot, and `fail_open`
bypasses the limit when full. `wait` requires a nonzero queue size. Omit the
admission setting for unbounded admission. Uses of the same shared model also
share its capacity; request deadlines include queue time.

Changing admission settings for a shared model requires stopping and restarting
the Router. A hot reload with different settings is rejected, and the active
configuration continues serving.

## Update a running model

Put a replacement model revision in a new directory, update its configuration,
then reload through the Dashboard or your existing management workflow.
The Router prepares the replacement before activating it. Failed preparation
leaves the current configuration running; existing requests finish before
old model resources are released.

A Dashboard change may be saved but still pending. For updates that return
`202`, poll `GET /api/router/api/v1/config/hash` through the Dashboard and wait
for `active_runtime_hash` to equal the update's `generated_runtime_hash`.
A competing change returns `409` while the first update is pending.

Knowledge-base updates keep old asset versions for active readers. Old versions
are retained on disk; automatic removal is not provided. See the
[management API reference](../../api/apiserver.md) for request and response details.

`serve` preserves configuration saved through the Dashboard or API. To replace
it with a local file, run
`vllm-sr serve --config config.yaml --replace-active-config`.
