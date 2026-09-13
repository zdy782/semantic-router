"""Explicit adapter or full-encoder optimization and checkpoint ownership."""

# ruff: noqa: PLC0415

import hashlib
import json
import math
from pathlib import Path

from .model import load_model, save_adapter
from .task_head import task_head_scope


def validate_method(method, adapter, fresh_head):
    if method not in {"lora", "full"}:
        raise ValueError("Training method must be lora or full")
    if method == "lora" and (adapter is None or fresh_head):
        raise ValueError("LoRA continuation requires its initialized adapter")
    if method == "full" and adapter is not None:
        raise ValueError(
            "Full training starts from a complete checkpoint, not an adapter"
        )


def load_trainable_model(base, contract, adapter, method, fresh_head=False):
    validate_method(method, adapter, fresh_head)
    model, tokenizer, labels, ids = load_model(
        base, contract, adapter, trainable=method == "lora"
    )
    if method == "full":
        if type(model).__name__ != "ModernBertForSequenceClassification":
            raise ValueError("Full sequence training requires a ModernBERT classifier")
        model.requires_grad_(True)
        if fresh_head:
            model.head.apply(model._init_weights)
            # ModernBERT initializes the final classifier on its owning task
            # module, not when visiting the bare Linear child.
            model._init_weights(model)
    return model, tokenizer, labels, ids


def optimizer_groups(model, learning_rate, head_learning_rate=None):
    rates = [learning_rate]
    if head_learning_rate is not None:
        rates.append(head_learning_rate)
    if any(not math.isfinite(rate) or rate <= 0 for rate in rates):
        raise ValueError("Learning rates must be finite and positive")
    base = model.get_base_model() if hasattr(model, "get_base_model") else model
    head_ids = {
        id(parameter)
        for module in (base.head, base.classifier)
        for parameter in module.parameters()
        if parameter.requires_grad
    }
    encoder, head = [], []
    for parameter in model.parameters():
        if parameter.requires_grad:
            (head if id(parameter) in head_ids else encoder).append(parameter)
    groups = []
    for name, parameters, rate in (
        ("encoder", encoder, learning_rate),
        ("task_head", head, head_learning_rate or learning_rate),
    ):
        if parameters:
            groups.append(
                {"name": name, "params": parameters, "lr": rate, "initial_lr": rate}
            )
    if not groups:
        raise ValueError("No trainable parameters")
    return groups


def initial_artifact_receipt(base, adapter):
    """Hash the actual local initialization, including every weight shard."""
    root = Path(base)
    if not root.is_dir():
        raise ValueError("Training requires a downloaded local base checkpoint")
    names = {"config.json", "tokenizer.json", "tokenizer_config.json"}
    for path in root.iterdir():
        if (
            path.suffix == ".safetensors"
            or path.name
            in {
                "model.safetensors.index.json",
                "pytorch_model.bin",
                "pytorch_model.bin.index.json",
            }
            or path.name.startswith("pytorch_model-")
        ):
            names.add(path.name)
    files = {}
    for name in sorted(names):
        path = root / name
        if path.is_file():
            with path.open("rb") as stream:
                files[name] = hashlib.file_digest(stream, "sha256").hexdigest()
    result = {"base_files": files}
    if adapter is not None:
        for filename in ("adapter_model.safetensors", "adapter_config.json"):
            path = Path(adapter) / filename
            if filename == "adapter_config.json" and not path.is_file():
                result[filename] = None
                continue
            with path.open("rb") as stream:
                result[filename] = hashlib.file_digest(stream, "sha256").hexdigest()
    return result


def verify_full_checkpoint(model, checkpoint):
    """Require every tensor of a complete sequence checkpoint to be preserved."""
    if type(model).__name__ != "ModernBertForSequenceClassification":
        raise ValueError("Full checkpoints must own the actual encoder weights")
    from safetensors.torch import load_file

    saved = load_file(str(Path(checkpoint) / "model.safetensors"), device="cpu")
    state = model.state_dict()
    if saved.keys() != state.keys():
        raise ValueError("Full checkpoint omitted or introduced model tensors")
    import torch

    for name, value in state.items():
        if saved[name].dtype != value.dtype or not torch.equal(
            saved[name], value.detach().cpu()
        ):
            raise ValueError(f"Full checkpoint changed tensor: {name}")


def save_training_checkpoint(model, tokenizer, destination, method, base_id, revision):
    if method == "lora":
        save_adapter(model, tokenizer, destination, base_id, revision)
        return
    if method != "full" or hasattr(model, "peft_config"):
        raise ValueError("Full checkpoints must own the actual encoder weights")
    destination.mkdir(parents=True, exist_ok=True)
    expected = task_head_scope(model)
    model.save_pretrained(destination, safe_serialization=True)
    verify_full_checkpoint(model, destination)
    tokenizer.save_pretrained(destination)
    (destination / "task-head.json").write_text(json.dumps(expected, indent=2) + "\n")
    (destination / "training-origin.json").write_text(
        json.dumps(
            {"method": method, "base_model": base_id, "base_revision": revision},
            indent=2,
        )
        + "\n"
    )
