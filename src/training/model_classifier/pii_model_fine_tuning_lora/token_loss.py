"""Explicit document weighting for token classification training."""

LOGIT_RANK = 3
IGNORE_INDEX = -100


def document_mean_loss(logits, labels, attention_mask):
    """Average each document's attended, nonignored token CE, then documents.

    Each document must have supervision. The trainer draws equally sized
    microbatches, so dividing this mean by the accumulation count gives equal
    weight to every document in the logical optimizer batch.
    """
    from torch.nn import functional  # noqa: PLC0415

    if (
        logits.ndim != LOGIT_RANK
        or labels.shape != logits.shape[:2]
        or attention_mask.shape != labels.shape
        or not logits.shape[0]
    ):
        raise ValueError("Expected batch/token logits, labels and attention mask")
    if not bool(((attention_mask == 0) | (attention_mask == 1)).all()):
        raise ValueError("Attention mask must contain only zero or one")
    valid = (labels != IGNORE_INDEX) & (attention_mask == 1)
    counts = valid.sum(dim=1)
    if bool((counts == 0).any()):
        raise ValueError("Every document needs at least one supervised token")
    effective_labels = labels.masked_fill(~valid, IGNORE_INDEX)
    token_losses = functional.cross_entropy(
        logits.float().transpose(1, 2),
        effective_labels,
        reduction="none",
        ignore_index=IGNORE_INDEX,
    )
    return (token_losses.sum(dim=1) / counts).mean()
