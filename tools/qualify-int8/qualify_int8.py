#!/usr/bin/env python3
"""Qualify int8 ONNX variants of vllm-sr classifier heads (issue #3225).

Per-head, per-platform pass/fail artifact:
  fp32 baseline -> quantize candidates -> quality metrics + latency.

Candidates:
  dynamic        ORT quantize_dynamic (control; reproduces the #3225 numbers)
  static_all     calibrated static PTQ, per-channel, all weight nodes
  static_no_mlp  static PTQ excluding MLP weight nodes (MLP stays fp32)
  static_no_attn static PTQ excluding attention weight nodes

Usage example (jailbreak head):
  python qualify_int8.py \
      --model-repo vllm-sr/mmbert32k-jailbreak-detector-merged \
      --dataset vllm-sr/jailbreak-detection-dataset \
      --eval-split test --calib-split validation \
      --positive-class 1 --threshold 0.7 \
      --profile macos-arm64-sdot-m4 --out artifacts/jailbreak_macm4.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import statistics
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
import onnx
import onnxruntime as ort
import pandas as pd
from huggingface_hub import HfApi, snapshot_download
from onnxruntime.quantization import (
    CalibrationDataReader,
    CalibrationMethod,
    QuantFormat,
    QuantType,
    quantize_dynamic,
    quantize_static,
)
from tokenizers import Tokenizer


# ---------------------------------------------------------------- data utils


def load_hf_parquet(repo: str, split: str, cache_dir: Path) -> pd.DataFrame:
    path = snapshot_download(
        repo_id=repo,
        repo_type="dataset",
        allow_patterns=[f"data/{split}-*.parquet", f"{split}.jsonl"],
        cache_dir=str(cache_dir),
    )
    files = sorted(Path(path).glob(f"data/{split}-*.parquet"))
    if files:
        return pd.concat([pd.read_parquet(f) for f in files], ignore_index=True)
    jl = Path(path) / f"{split}.jsonl"
    if jl.exists():
        return pd.read_json(jl, lines=True)
    raise FileNotFoundError(f"{repo} has no {split} parquet/jsonl")


def download_onnx_pkg(repo: str, cache_dir: Path) -> Path:
    path = snapshot_download(
        repo_id=repo,
        repo_type="model",
        allow_patterns=[
            "onnx/model.onnx",
            "onnx/*.json",
            "onnx/tokenizer*",
        ],
        cache_dir=str(cache_dir),
    )
    onnx_dir = Path(path) / "onnx"
    if not onnx_dir.is_dir():
        raise FileNotFoundError(f"{repo} ships no onnx/ directory")
    return onnx_dir


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 22), b""):
            h.update(chunk)
    return h.hexdigest()


# ---------------------------------------------------------------- ORT utils


def make_session(model_path: Path, threads: int) -> ort.InferenceSession:
    so = ort.SessionOptions()
    so.intra_op_num_threads = threads
    so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    return ort.InferenceSession(
        str(model_path), sess_options=so, providers=["CPUExecutionProvider"]
    )


def model_input_names(sess: ort.InferenceSession) -> list[str]:
    return [i.name for i in sess.get_inputs()]


def tokenize_batch(
    tokenizer: Tokenizer, texts: list[str], max_len: int | None,
    fixed_len: bool = False,
) -> dict[str, np.ndarray]:
    encodings = [tokenizer.encode(t) for t in texts]
    if max_len is not None:
        for e in encodings:
            e.truncate(max_len)
    maxlen = max_len if (fixed_len and max_len) else max(len(e.ids) for e in encodings)
    input_ids = np.zeros((len(encodings), maxlen), dtype=np.int64)
    attn = np.zeros((len(encodings), maxlen), dtype=np.int64)
    ttype = np.zeros((len(encodings), maxlen), dtype=np.int64)
    for i, e in enumerate(encodings):
        input_ids[i, : len(e.ids)] = e.ids
        attn[i, : len(e.attention_mask)] = e.attention_mask
        if e.type_ids:
            ttype[i, : len(e.type_ids)] = e.type_ids
    return {
        "input_ids": input_ids,
        "attention_mask": attn,
        "token_type_ids": ttype,
    }


def run_probs(
    sess: ort.InferenceSession,
    tokenizer: Tokenizer,
    texts: list[str],
    batch_size: int,
    max_len: int | None,
) -> np.ndarray:
    names = model_input_names(sess)
    out_name = sess.get_outputs()[0].name
    probs = []
    for i in range(0, len(texts), batch_size):
        feats = tokenize_batch(tokenizer, texts[i : i + batch_size], max_len)
        feed = {n: feats[n] for n in names if n in feats}
        logits = sess.run([out_name], feed)[0]
        logits = np.asarray(logits, dtype=np.float64)
        if logits.ndim == 3:  # token-level head: mean-pool over valid tokens
            mask = feed["attention_mask"][..., None]
            logits = (logits * mask).sum(1) / np.clip(mask.sum(1), 1, None)
        e = np.exp(logits - logits.max(-1, keepdims=True))
        probs.append(e / e.sum(-1, keepdims=True))
    return np.concatenate(probs)


def bench_latency(
    sess: ort.InferenceSession,
    tokenizer: Tokenizer,
    text: str,
    lengths: list[int],
    iters: int,
    warmup: int,
) -> dict[str, float]:
    names = model_input_names(sess)
    out_name = sess.get_outputs()[0].name
    results = {}
    for length in lengths:
        feats = tokenize_batch(tokenizer, [text], None)
        ids = feats["input_ids"][0]
        if len(ids) < length:
            reps = int(np.ceil(length / max(len(ids), 1)))
            ids = np.tile(ids, reps)[:length]
        else:
            ids = ids[:length]
        feed = {"input_ids": ids[None, :].astype(np.int64),
                "attention_mask": np.ones((1, len(ids)), dtype=np.int64),
                "token_type_ids": np.zeros((1, len(ids)), dtype=np.int64)}
        feed = {n: feed[n] for n in names if n in feed}
        for _ in range(warmup):
            sess.run([out_name], feed)
        times = []
        for _ in range(iters):
            t0 = time.perf_counter()
            sess.run([out_name], feed)
            times.append((time.perf_counter() - t0) * 1000.0)
        results[f"len{length}"] = round(statistics.median(times), 3)
    return results


# ------------------------------------------------------------------ metrics


def accuracy(probs: np.ndarray, labels: np.ndarray) -> float:
    return float((probs.argmax(1) == labels).mean())


def macro_f1(probs: np.ndarray, labels: np.ndarray) -> float:
    preds = probs.argmax(1)
    f1s = []
    for c in np.unique(labels):
        tp = int(((preds == c) & (labels == c)).sum())
        fp = int(((preds == c) & (labels != c)).sum())
        fn = int(((preds != c) & (labels == c)).sum())
        denom = 2 * tp + fp + fn
        f1s.append(0.0 if denom == 0 else 2 * tp / denom)
    return float(np.mean(f1s))


def ece(probs: np.ndarray, labels: np.ndarray, bins: int = 15) -> float:
    conf = probs.max(1)
    correct = (probs.argmax(1) == labels).astype(np.float64)
    total = 0.0
    for lo in np.linspace(0, 1, bins + 1)[:-1]:
        hi = lo + 1.0 / bins
        m = (conf >= lo) & (conf < hi if hi < 1 else conf <= hi)
        if m.any():
            total += m.mean() * abs(correct[m].mean() - conf[m].mean())
    return float(total)


def binary_gate_metrics(
    probs: np.ndarray, labels: np.ndarray, pos: int, thr: float
) -> dict[str, float]:
    p = probs[:, pos]
    fire = p >= thr
    pos_mask = labels == pos
    neg_mask = ~pos_mask
    det = float((fire & pos_mask).sum() / pos_mask.sum()) if pos_mask.any() else 0.0
    fpr = float((fire & neg_mask).sum() / neg_mask.sum()) if neg_mask.any() else 0.0
    return {f"det@{thr}": det, f"fpr@{thr}": fpr}


def agreement(probs: np.ndarray, ref_probs: np.ndarray) -> float:
    return float((probs.argmax(1) == ref_probs.argmax(1)).mean())


def quality_metrics(
    probs: np.ndarray,
    labels: np.ndarray,
    ref_probs: np.ndarray | None,
    pos: int | None,
    thr: float,
) -> dict[str, float]:
    m = {
        "acc": round(accuracy(probs, labels), 4),
        "macroF1": round(macro_f1(probs, labels), 4),
        "ece": round(ece(probs, labels), 4),
        "agreement_with_fp32": (
            round(agreement(probs, ref_probs), 4) if ref_probs is not None else 1.0
        ),
    }
    if pos is not None:
        m.update({k: round(v, 4) for k, v in binary_gate_metrics(probs, labels, pos, thr).items()})
    return m


# --------------------------------------------------------------- quantize


class TextCalibrationReader(CalibrationDataReader):
    def __init__(self, sess: ort.InferenceSession, tokenizer: Tokenizer,
                 texts: list[str], max_len: int | None):
        self.names = model_input_names(sess)
        self.tokenizer = tokenizer
        self.texts = texts
        self.max_len = max_len
        self.iter_ = iter(range(len(texts)))

    def get_next(self) -> dict | None:
        try:
            i = next(self.iter_)
        except StopIteration:
            return None
        feats = tokenize_batch(self.tokenizer, [self.texts[i]],
                               self.max_len, fixed_len=True)
        return {n: feats[n] for n in self.names if n in feats}

    def rewind(self):
        self.iter_ = iter(range(len(self.texts)))


def weight_node_names(model_path: Path) -> dict[str, list[str]]:
    """Classify weight-bearing MatMul/Gemm nodes into attn / mlp / other."""
    model = onnx.load(str(model_path), load_external_data=False)
    names = {"attn": [], "mlp": [], "other": []}
    for node in model.graph.node:
        if node.op_type not in ("MatMul", "Gemm"):
            continue
        lname = node.name.lower()
        if re.search(r"mlp|dense_h_to_4h|dense_4h_to_h|intermediate|wi_|wo(?!.*attn)|ffn|feedforward", lname) and "attn" not in lname:
            names["mlp"].append(node.name)
        elif re.search(r"attn|attention|wq|wk|wv|qkv|self\.attention", lname):
            names["attn"].append(node.name)
        else:
            names["other"].append(node.name)
    return names


CALIBRATE_METHODS = {
    "minmax": CalibrationMethod.MinMax,
    "entropy": CalibrationMethod.Entropy,
    "percentile": CalibrationMethod.Percentile,
}


def build_variants(
    fp32_path: Path,
    sess: ort.InferenceSession,
    tokenizer: Tokenizer,
    calib_texts: list[str],
    calib_max_len: int | None,
    workdir: Path,
    calibrate_methods: list[str],
) -> dict[str, tuple[Path, dict]]:
    variants: dict[str, tuple[Path, dict]] = {}
    reader = TextCalibrationReader(sess, tokenizer, calib_texts, calib_max_len)

    dyn_path = workdir / "model_int8_dynamic.onnx"
    quantize_dynamic(str(fp32_path), str(dyn_path),
                     weight_type=QuantType.QInt8, per_channel=True)
    variants["dynamic"] = (dyn_path, {
        "method": "dynamic", "weight_type": "QInt8", "per_channel": True,
        "activation_type": "dynamic", "calibrated": False,
    })

    groups = weight_node_names(fp32_path)
    print(f"[quant] node groups: attn={len(groups['attn'])} "
          f"mlp={len(groups['mlp'])} other={len(groups['other'])}")

    def static(name: str, exclude: list[str], method: str) -> tuple[Path, dict]:
        out = workdir / f"model_int8_{name}.onnx"
        reader.rewind()
        quantize_static(
            str(fp32_path), str(out), reader,
            quant_format=QuantFormat.QDQ,
            calibrate_method=CALIBRATE_METHODS[method],
            activation_type=QuantType.QUInt8,
            weight_type=QuantType.QInt8,
            per_channel=True,
            nodes_to_exclude=exclude,
        )
        return out, {
            "method": "static_qdq", "calibrate_method": method,
            "activation_type": "QUInt8", "weight_type": "QInt8",
            "per_channel": True, "calibrated": True,
            "nodes_excluded": len(exclude),
        }

    for method in calibrate_methods:
        variants[f"static_{method}_all"] = static(f"{method}_all", [], method)
    variants["static_no_mlp"] = static("no_mlp", groups["mlp"], calibrate_methods[0])
    variants["static_no_attn"] = static("no_attn", groups["attn"], calibrate_methods[0])
    return variants


# ------------------------------------------------------------ pass / fail


def judge(
    base: dict[str, float],
    cand: dict[str, float],
    budget: dict[str, float],
    pos: int | None,
    thr: float,
) -> dict:
    checks = {
        "acc_drop_pts": round((base["acc"] - cand["acc"]) * 100, 2),
        "macroF1_drop_pts": round((base["macroF1"] - cand["macroF1"]) * 100, 2),
        "agreement": cand["agreement_with_fp32"],
    }
    verdicts = [
        checks["acc_drop_pts"] <= budget["acc_drop_pts"],
        checks["macroF1_drop_pts"] <= budget["macroF1_drop_pts"],
        checks["agreement"] >= budget["agreement_min"],
    ]
    if pos is not None:
        key = f"fpr@{thr}"
        checks["fpr_delta_pts"] = round((cand[key] - base[key]) * 100, 2)
        verdicts.append(checks["fpr_delta_pts"] <= budget["fpr_delta_pts"])
    checks["pass"] = all(verdicts)
    return checks


# -------------------------------------------------------------------- main


def hf_revision(repo: str, repo_type: str) -> str | None:
    try:
        info = HfApi().repo_info(repo, repo_type=repo_type)
        return getattr(info, "sha", None)
    except Exception:
        return None


def cpu_flags_raw() -> str:
    if Path("/proc/cpuinfo").exists():
        for line in Path("/proc/cpuinfo").read_text(errors="ignore").splitlines():
            low = line.lower()
            if low.startswith("flags") or low.startswith("features"):
                return line.split(":", 1)[-1].strip()
    if platform.system() == "Darwin":
        try:
            return subprocess.check_output(
                ["sysctl", "-n", "machdep.cpu.features"],
                text=True, stderr=subprocess.DEVNULL).strip()
        except Exception:
            pass
    return ""


def detect_profile() -> str:
    machine = platform.machine()
    system = platform.system()
    flags = ""
    if system == "Linux" and Path("/proc/cpuinfo").exists():
        flags = Path("/proc/cpuinfo").read_text(errors="ignore").lower()
    elif system == "Darwin":
        try:
            flags = subprocess.check_output(
                ["sysctl", "-n", "machdep.cpu.features"],
                text=True, stderr=subprocess.DEVNULL).lower()
        except Exception:
            flags = ""
    tags = []
    if machine in ("aarch64", "arm64"):
        for feat in ("asimddp", "i8mm", "sve", "sve2", "sme"):
            if feat in flags:
                tags.append(feat)
        if not tags:
            tags.append("neon")
    elif machine in ("x86_64", "amd64"):
        for feat in ("avx512_vnni", "avx512f", "avx_vnni", "avx2", "vnni"):
            if feat in flags:
                tags.append(feat)
    return f"{system.lower()}-{machine}-{'_'.join(dict.fromkeys(tags)) or 'generic'}"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--model-repo", required=True)
    ap.add_argument("--dataset", required=True)
    ap.add_argument("--eval-split", default="test")
    ap.add_argument("--calib-split", default="validation")
    ap.add_argument("--text-col", default="text")
    ap.add_argument("--label-col", default="label")
    ap.add_argument("--positive-class", type=int, default=None,
                    help="set for binary gate metrics (det@/FPR@)")
    ap.add_argument("--threshold", type=float, default=0.7)
    ap.add_argument("--eval-max", type=int, default=0, help="cap eval rows (0=all)")
    ap.add_argument("--calib-samples", type=int, default=512)
    ap.add_argument("--eval-max-len", type=int, default=0, help="truncate (0=off)")
    ap.add_argument("--calib-max-len", type=int, default=512)
    ap.add_argument("--batch-size", type=int, default=8)
    ap.add_argument("--threads", type=int, default=8)
    ap.add_argument("--bench-iters", type=int, default=50)
    ap.add_argument("--bench-warmup", type=int, default=20)
    ap.add_argument("--bench-lengths", default="32,128,512")
    ap.add_argument("--calibrate-methods", default="minmax",
                    help="comma list: minmax,entropy,percentile")
    ap.add_argument("--quiet", action="store_true",
                    help="silence onnxruntime quantization warnings")
    ap.add_argument("--profile", default="")
    ap.add_argument("--cache-dir", default=".hf_cache")
    ap.add_argument("--out", required=True)
    ap.add_argument("--budget-acc-drop", type=float, default=1.5)
    ap.add_argument("--budget-f1-drop", type=float, default=1.5)
    ap.add_argument("--budget-fpr-delta", type=float, default=1.0)
    ap.add_argument("--budget-agreement", type=float, default=0.95)
    args = ap.parse_args()

    if args.quiet:
        import logging
        logging.getLogger("root").setLevel(logging.ERROR)
        ort.set_default_logger_severity(3)

    profile = args.profile or detect_profile()
    cache = Path(args.cache_dir)
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    workdir = out_path.parent / f"quant_{out_path.stem}"
    workdir.mkdir(exist_ok=True)

    print(f"[setup] profile={profile} ort={ort.__version__}")
    onnx_dir = download_onnx_pkg(args.model_repo, cache)
    fp32_path = onnx_dir / "model.onnx"
    tokenizer = Tokenizer.from_file(str(onnx_dir / "tokenizer.json"))

    eval_df = load_hf_parquet(args.dataset, args.eval_split, cache)
    if args.eval_max:
        eval_df = eval_df.head(args.eval_max)
    texts = eval_df[args.text_col].tolist()
    labels = eval_df[args.label_col].to_numpy()
    calib_df = load_hf_parquet(args.dataset, args.calib_split, cache)
    calib_texts = calib_df[args.text_col].sample(
        n=min(args.calib_samples, len(calib_df)), random_state=0).tolist()
    print(f"[data] eval={len(texts)} rows from {args.dataset}:{args.eval_split}, "
          f"calib={len(calib_texts)} from {args.calib_split}")

    eval_max_len = args.eval_max_len or None
    calib_max_len = args.calib_max_len or None
    bench_lengths = [int(x) for x in args.bench_lengths.split(",")]

    print("[fp32] baseline eval ...")
    sess_fp32 = make_session(fp32_path, args.threads)
    probs_fp32 = run_probs(sess_fp32, tokenizer, texts, args.batch_size, eval_max_len)
    base = quality_metrics(probs_fp32, labels, None, args.positive_class, args.threshold)
    bench_text = texts[len(texts) // 2]
    base_latency = bench_latency(sess_fp32, tokenizer, bench_text,
                                 bench_lengths, args.bench_iters, args.bench_warmup)
    print(f"[fp32] {base} latency={base_latency}")

    print("[quant] building int8 variants ...")
    calibrate_methods = [m.strip() for m in args.calibrate_methods.split(",")]
    variant_paths = build_variants(fp32_path, sess_fp32, tokenizer,
                                   calib_texts, calib_max_len, workdir,
                                   calibrate_methods)

    budget = {"acc_drop_pts": args.budget_acc_drop,
              "macroF1_drop_pts": args.budget_f1_drop,
              "fpr_delta_pts": args.budget_fpr_delta,
              "agreement_min": args.budget_agreement}

    artifact = {
        "issue": "vllm-project/semantic-router#3225",
        "profile": profile,
        "host": {
            "platform": platform.platform(),
            "machine": platform.machine(),
            "processor": platform.processor(),
            "cpu_feature_tags": detect_profile(),
            "cpu_flags": cpu_flags_raw(),
        },
        "ort_version": ort.__version__,
        "model_repo": args.model_repo,
        "model_revision": hf_revision(args.model_repo, "model"),
        "model_file_sha256": sha256_file(fp32_path),
        "dataset": f"{args.dataset}:{args.eval_split}",
        "dataset_revision": hf_revision(args.dataset, "dataset"),
        "eval_rows": int(len(labels)),
        "calibration": {
            "split": args.calib_split,
            "samples": len(calib_texts),
            "selection": "pandas sample(random_state=0)",
            "max_len": args.calib_max_len,
            "padding": "fixed_length",
        },
        "threshold": args.threshold,
        "positive_class": args.positive_class,
        "run": {
            "intra_op_threads": args.threads,
            "eval_batch_size": args.batch_size,
            "eval_max_len": args.eval_max_len,
            "bench_lengths": bench_lengths,
            "bench_iters": args.bench_iters,
            "bench_warmup": args.bench_warmup,
        },
        "budget": budget,
        "baseline_fp32": {"quality": base, "latency_ms_p50": base_latency,
                          "size_mb": round(fp32_path.stat().st_size / 1e6, 1)},
        "variants": {},
    }

    for name, (path, meta) in variant_paths.items():
        print(f"[{name}] eval ...")
        sess = make_session(path, args.threads)
        probs = run_probs(sess, tokenizer, texts, args.batch_size, eval_max_len)
        q = quality_metrics(probs, labels, probs_fp32, args.positive_class, args.threshold)
        lat = bench_latency(sess, tokenizer, bench_text, bench_lengths,
                            args.bench_iters, args.bench_warmup)
        verdict = judge(base, q, budget, args.positive_class, args.threshold)
        artifact["variants"][name] = {
            "file": path.name,
            "file_sha256": sha256_file(path),
            "size_mb": round(path.stat().st_size / 1e6, 1),
            "quant": meta,
            "quality": q,
            "latency_ms_p50": lat,
            "checks": verdict,
        }
        print(f"[{name}] {q} latency={lat} checks={verdict}")

    with open(out_path, "w") as f:
        json.dump(artifact, f, indent=2)
    print(f"[done] artifact -> {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
