"""Absolute semantic anchors and full logical-batch geometry distillation."""

from __future__ import annotations

import torch
from torch.nn import functional

from .newbase_objectives import relational_cosine_loss

_MATRIX_DIMENSIONS = 2


def pointwise_cosine_loss(student, teacher):
    """Mean angular distance, without an implicit division by embedding width.

    This same-width objective transfers absolute coordinates. A different-width
    teacher requires relation distillation or an explicit learned projection.
    """
    if (
        student.ndim != _MATRIX_DIMENSIONS
        or student.shape != teacher.shape
        or not student.numel()
    ):
        raise ValueError("Pointwise anchors require nonempty matching matrices")
    if not torch.isfinite(student).all() or not torch.isfinite(teacher).all():
        raise ValueError("Pointwise anchors must be finite")
    if (student.norm(dim=-1) == 0).any() or (teacher.norm(dim=-1) == 0).any():
        raise ValueError("A zero vector has no angular target")
    left = functional.normalize(student.float(), dim=-1)
    right = functional.normalize(teacher.detach().float(), dim=-1)
    # Squared distance avoids negative loss from a dot product rounded above 1.
    return (left - right).square().sum(-1).mean() / 2


def all_exit_anchor_loss(values, teacher, exits):
    """Explicit Matryoshka prefixes of one same-width teacher target.

    Prefixes are re-normalized, never used to hide different teacher widths.
    Every selected depth receives the target in the same coordinate system.
    """
    if teacher.ndim != _MATRIX_DIMENSIONS or teacher.shape[1] != exits.dimensions[0]:
        raise ValueError("Anchor teacher must match the full student width")
    return sum(
        weight * pointwise_cosine_loss(values[key], teacher[:, : key[1]])
        for key, weight in exits.weighted()
    )


def full_batch_relation_loss(student, teacher, component_ids, components):
    """Cross-parent relations across the entire logical batch, with stop-gradient."""
    if len(component_ids) != len(student):
        raise ValueError("Relation identities and logical batch differ")
    mask = torch.tensor(
        [
            [
                components[a]["normalized_sha256"] != components[b]["normalized_sha256"]
                and not set(components[a]["parent_groups"])
                & set(components[b]["parent_groups"])
                for b in component_ids
            ]
            for a in component_ids
        ],
        dtype=torch.bool,
        device=student.device,
    )
    return relational_cosine_loss(student, student, teacher, teacher, mask)
