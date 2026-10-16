# #3225 int8 classifier qualification harness

目标：产出 vllm-project/semantic-router#3225 要求的第一交付物——
**per-head × per-platform 的 int8 量化 pass/fail 记录**。

做法：fp32 `model.onnx` 基线 → 构建 int8 候选 → 同一 eval 集跑质量指标 +
定长延迟 → 按预算判 pass/fail → JSON artifact。

## 候选变体

| variant | 方法 |
|---|---|
| `dynamic` | ORT quantize_dynamic per-channel（对照组，复现 subin9 的数） |
| `static_minmax_all` | 校准静态 PTQ（MinMax）全部 weight 节点 |
| `static_entropy_all` / `static_percentile_all` | 换校准算法（`--calibrate-methods` 控制） |
| `static_no_mlp` | 排除 MLP 节点（MLP 保持 fp32，混合精度） |
| `static_no_attn` | 排除 attention 节点 |

## 指标

acc / macroF1 / ECE(15bin) / det@T / FPR@T（二分类头）/ agreement-with-fp32。
延迟：batch1、len{32,128,512}、p50。

## 安装

```bash
python3 -m venv .venv
# 国内源；也可直接 pip install
uv pip install --python .venv/bin/python \
    -i https://mirrors.aliyun.com/pypi/simple/ \
    onnxruntime onnx numpy tokenizers huggingface_hub pandas pyarrow
# 或: .venv/bin/pip install onnxruntime onnx numpy tokenizers huggingface_hub pandas pyarrow
```

依赖刻意做轻：不用 torch/transformers/sklearn（tokenizer.json 直接喂 `tokenizers`）。

## 跑法

jailbreak 头（二分类，阈值 0.7）：

```bash
.venv/bin/python qualify_int8.py \
    --model-repo vllm-sr/mmbert32k-jailbreak-detector-merged \
    --dataset vllm-sr/jailbreak-detection-dataset \
    --eval-split test --calib-split validation \
    --positive-class 1 --threshold 0.7 \
    --calibrate-methods minmax,entropy,percentile \
    --calib-samples 512 --batch-size 8 --threads 8 \
    --profile linux-x86_64-avx512_vnni \
    --out artifacts/jailbreak_<profile>.json --quiet
```

modality 头（三分类，无阈值指标）：

```bash
.venv/bin/python qualify_int8.py \
    --model-repo vllm-sr/mmbert32k-modality-router-merged \
    --dataset vllm-sr/modality-routing-dataset \
    --eval-split test --calib-split validation \
    --calibrate-methods minmax,entropy,percentile \
    --calib-samples 512 --batch-size 8 --threads 8 \
    --profile linux-aarch64-asimddp-kunpeng920 \
    --out artifacts/modality_<profile>.json --quiet
```

`--profile` 不传会自动探测（linux 读 /proc/cpuinfo，darwin 读 sysctl）。
建议显式写清机器名，例如 `linux-x86_64-avx512_vnni-icelake`、
`linux-x86_64-avx2-novnni`、`linux-aarch64-asimddp-kunpeng920`、`linux-aarch64-i8mm-n2`。
鲲鹏 920 是 ARMv8.2（asimddp 有、无 i8mm/SVE）——`lscpu | grep -o 'asimddp\|i8mm\|sve'` 可确认。

## 预算（默认，可用 --budget-* 覆盖）

acc 下降 ≤1.5pt、macroF1 下降 ≤1.5pt、FPR 增量 ≤1.0pt、agreement ≥0.95。
预算是 issue 交付物的一部分——定稿前在 issue 里和维护者对一下数值。

## 输出

`artifacts/*.json`：含 host 平台、ORT 版本、模型 sha256、行数、阈值、
fp32 基线、每个变体的质量/延迟/checks.pass——即 issue 要的
"explicit pass/fail artifact"。

## 冒烟已验证（darwin-arm64, 24+24 样本）

- 管线全通：下载 → fp32 → 4 变体 → artifact
- dynamic int8 ≈ 1.9–2.3x 加速（len32: 35.4→18.2ms, len128: 137→59ms），与 subin9 吻合
- 小样本校准质量不可信（24 条），正式跑必须用 256–512 条校准
- 节点分组：attn=89 mlp=44 other=2，与 issue 里"~90 权重 MatMul"一致
