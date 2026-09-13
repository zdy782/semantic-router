---
title: 运维与故障排查
description: 检查就绪状态、限制模型并发并更新运行中的模型。
translation:
  source_commit: "b2f672651b66f00e3410d5b58b5d6d8cb883cfad"
  source_file: "docs/installation/runtime/lifecycle-diagnostics.md"
  outdated: false
---

配置好[进程内模型](in-process.md)或[外部服务](external.md)后，使用本页进行检查。

## 检查启动状态 {#check-startup}

```bash
vllm-sr config validate --config config.yaml
vllm-sr serve --config config.yaml
curl -fsS http://localhost:8080/startup-status
```

验证命令检查配置。启动时，Router 再加载或连接模型，并检查已启用功能所需的能力。GPU 内核编译可能使首次启动比后续请求耗时更长。

本地 Docker 部署可使用 `vllm-sr serve --startup-timeout 7200`，在容器启动后最多等待 7200 秒就绪。默认值为 1800 秒，参数接受正整数；应根据配置的模型、输入上限和硬件的实测启动时间选择。CLI 会限制每次就绪探测的耗时，超时后最多再用 5 秒收集诊断日志。超时不会停止容器、取消模型加载或改变推理请求时限。先通过 `vllm-sr status` 和 `vllm-sr logs router` 检查，再决定是否停止栈。

| 问题 | 检查项 |
| --- | --- |
| 模型无法加载 | 权重或 ONNX 文件是否完整，以及分词器、标签和挂载路径 |
| 引擎或设备不可用 | 镜像和主机是否匹配所选 CPU/GPU 运行环境 |
| 标签不匹配 | 模型标签顺序，以及规则的标签或映射文件 |
| 不支持嵌入层或维度 | 导出所需层，并与使用方或已存索引匹配 |
| 远程推理失败 | 服务地址、凭据、超时、响应格式和大小限制 |
| 置信度为 `null` | 结果没有模型分数；见[安全模型](safety.md#handle-failures-and-missing-scores) |

## AMD 启动问题 {#amd-startup-problems}

显式选择执行提供方：`rocm:N` 使用 ROCm，`migraphx:N` 使用 MIGraphX。镜像必须包含所选提供方及模型图所需的运行库。CK 图还需要受信任的 `ck_flash_attention` 自定义算子配置；准备会话时会校验其库的身份，仅有配置名称不能证明实际执行路径。

使用维护的 MIGraphX 镜像时，保留 `MIGRAPHX_MLIR_USE_SPECIFIC_OPS=~attention`，以禁用 MLIR attention fusion。

| 错误或现象 | 处理方式 |
| --- | --- |
| 模型图的算子不受支持 | 检查模型图与所选执行提供方是否匹配；为其他引擎导出的图不能直接互换 |
| GPU 嵌入缺少输入预算 | 将部署的 `input.max_tokens` 设为正数；见[嵌入模型](embeddings.md#amd-gpu) |
| 模型在 GPU 准备阶段失败 | 检查图和运行库；请求的 GPU 执行不会回退到 CPU |
| 首次启动耗时明显较长 | 为编译和每个所需嵌入层的预热留出时间 |

使用 MIGraphX 时，取消设置以下进程环境变量，改用 deployment 配置精度：

```text
ORT_MIGRAPHX_FP16_ENABLE
ORT_MIGRAPHX_BF16_ENABLE
ORT_MIGRAPHX_FP8_ENABLE
ORT_MIGRAPHX_INT8_ENABLE
ORT_MIGRAPHX_MODEL_CACHE_PATH
```

任何非空值（包括 `0`）都会被拒绝，因为它们可能覆盖配置的精度或已编译模型。维护的镜像不设置这些变量。

## 检查实际执行路径 {#inspect-the-executed-path}

使用 `POST /api/v1/routing/preview?trace=true`，提交实际需要路由的请求和 recipe。Preview 执行配置的路由信号，返回匹配结果、数值、错误和路由轨迹，不调用生成后端，也不执行 RAG 检索或 rerank 插件。请求格式见[API 参考](/zh-Hans/docs/api/apiserver)。

通过启动和模型运行时记录确认实际的执行提供方、精度和有效输入上限。配置 AMD 设备本身不能证明 GPU 执行；原生 ORT 路径会拒绝请求的 GPU 会话回退到 CPU。比较 CPU、ROCm 和 CUDA 时，应保留这一差别。

真实 RAG 请求的推理 span 会记录 `rag.rerank_latency_seconds`、`rag.rerank_candidates`、`rag.reranker_identity` 和原始相关性分数。缓存上下文不代表本次执行了 reranker。分别报告模型推理、排队、检索与后端生成耗时；Preview 延迟不是端到端响应延迟。

## 限制推理并发 {#limit-concurrent-inference}

对于[进程内模型](in-process.md)示例中的 `email-risk-cpu` 部署，以下设置允许两个并发调用、八个排队请求，排队超时为一秒：

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

`shed` 拒绝超出容量的请求，`wait` 等待队列空位，`fail_open` 在满载时绕过限制。`wait` 要求队列大小非零。不配置 admission 时，不施加并发准入限制。共享同一个模型的调用也共享其容量；请求期限包含排队时间。

更改共享模型的并发与排队设置后，需要停止并重新启动 Router。此类热更新会被拒绝，当前配置继续提供服务。

## 更新运行中的模型 {#update-a-running-model}

将新的模型 revision 放入新目录，更新配置，再通过控制面板或现有管理流程重载。Router 在激活前准备新模型。准备失败时，当前配置继续运行；旧模型资源会在已有请求完成后释放。

控制面板更改可能已保存但尚未激活。对于返回 `202` 的更新，通过控制面板轮询 `GET /api/router/api/v1/config/hash`，等待 `active_runtime_hash` 与该次更新的 `generated_runtime_hash` 相同。第一项更新尚未激活时，另一项写入会返回 `409`。

知识库更新会保留旧资产版本，供仍在运行的读取使用。旧版本保留在磁盘上，目前不自动清理。请求和响应详情见[管理 API 参考](/zh-Hans/docs/api/apiserver)。

`serve` 会保留通过控制面板或 API 保存的配置。要改用本地文件，请运行 `vllm-sr serve --config config.yaml --replace-active-config`。
