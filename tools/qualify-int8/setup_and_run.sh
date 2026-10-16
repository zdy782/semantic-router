#!/bin/bash
# #3225 qualification - server one-shot
# 用法: bash setup_and_run.sh <profile-name> [jailbreak|modality|both]
# 例:   bash setup_and_run.sh linux-x86_64-avx512_vnni-zen4 both
set -e
cd "$(dirname "$0")"
PROFILE="${1:?need profile name, e.g. linux-aarch64-asimddp-kunpeng920}"
HEADS="${2:-both}"
MIRROR="${PIP_MIRROR:-https://mirrors.aliyun.com/pypi/simple/}"

if [ ! -d .venv ]; then
  python3 -m venv .venv
fi
.venv/bin/pip install -q -i "$MIRROR" \
    onnxruntime onnx numpy tokenizers huggingface_hub pandas pyarrow

run_head() {
  local repo dataset pc thr out
  if [ "$1" = jailbreak ]; then
    repo=vllm-sr/mmbert32k-jailbreak-detector-merged
    dataset=vllm-sr/jailbreak-detection-dataset
    pc="--positive-class 1 --threshold 0.7"
  else
    repo=vllm-sr/mmbert32k-modality-router-merged
    dataset=vllm-sr/modality-routing-dataset
    pc=""
  fi
  out="artifacts/${1}_${PROFILE}.json"
  .venv/bin/python qualify_int8.py \
      --model-repo "$repo" --dataset "$dataset" \
      --eval-split test --calib-split validation \
      $pc \
      --calibrate-methods "${CALIB_METHODS:-minmax}" \
      --calib-samples "${CALIB_SAMPLES:-128}" --batch-size 8 --threads "${THREADS:-16}" \
      --profile "$PROFILE" --out "$out" --quiet
  echo "[done] $out"
}

case "$HEADS" in
  jailbreak) run_head jailbreak ;;
  modality)  run_head modality ;;
  both)      run_head jailbreak; run_head modality ;;
  *) echo "unknown head: $HEADS"; exit 1 ;;
esac
