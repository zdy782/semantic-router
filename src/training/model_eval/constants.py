"""
Constants for served-model evaluation and explicit legacy MoM evaluation
All shared constants, registries and configs are defined here.
"""

from copy import deepcopy

# Historical reference only; loaders must use the artifact's declared base.
BASE_MODEL_ID = "jhu-clsp/mmBERT-base"

# Supported langs
LANGUAGE_CODES = {
    "en": "English",
    "es": "Spanish",
    "fr": "French",
    "de": "German",
    "zh": "Chinese",
    "ja": "Japanese",
    "ar": "Arabic",
    "hi": "Hindi",
    "pt": "Portuguese",
    "it": "Italian",
}

# Registry of all MoM models (merged as well as LoRA)
LEGACY_MODEL_REGISTRY = {
    "feedback": {
        "id": "llm-semantic-router/mmbert32k-feedback-detector-merged",
        "lora_id": "llm-semantic-router/mmbert32k-feedback-detector-lora",
        "type": "text_classification",
        "hf_dataset": "llm-semantic-router/feedback-detector-dataset",
        "labels": ["SAT", "NEED_CLARIFICATION", "WRONG_ANSWER", "WANT_DIFFERENT"],
        "text_col": "text",
        "label_col": "label",
        "split": "validation",
    },
    "jailbreak": {
        "id": "llm-semantic-router/mmbert32k-jailbreak-detector-merged",
        "lora_id": "llm-semantic-router/mmbert32k-jailbreak-detector-lora",
        "type": "text_classification",
        "hf_dataset": "llm-semantic-router/jailbreak-detection-dataset",
        "labels": ["benign", "jailbreak"],
        "dataset_label_aliases": {"safe": "benign", "unsafe": "jailbreak"},
        "text_col": "text",
        "label_col": "label",
        "split": "test",
    },
    "fact-check": {
        "id": "llm-semantic-router/mmbert32k-factcheck-classifier-merged",
        "lora_id": "llm-semantic-router/mmbert32k-factcheck-classifier-lora",
        "type": "text_classification",
        "hf_dataset": "llm-semantic-router/fact-check-classification-dataset",
        "labels": ["NO_FACT_CHECK_NEEDED", "FACT_CHECK_NEEDED"],
        "text_col": "text",
        "label_col": "label_id",
        "split": "test",
    },
    "intent": {
        "id": "llm-semantic-router/mmbert32k-intent-classifier-merged",
        "lora_id": "llm-semantic-router/mmbert32k-intent-classifier-lora",
        "type": "text_classification",
        "hf_dataset": "TIGER-Lab/MMLU-Pro",
        "labels": [
            "biology",
            "business",
            "chemistry",
            "computer science",
            "economics",
            "engineering",
            "health",
            "history",
            "law",
            "math",
            "other",
            "philosophy",
            "physics",
            "psychology",
        ],
        "text_col": "question",
        "label_col": "category",
        "split": "test",
    },
    "pii": {
        "id": "llm-semantic-router/mmbert32k-pii-detector-merged",
        "lora_id": "llm-semantic-router/mmbert32k-pii-detector-lora",
        "type": "token_classification",
        "hf_dataset": "presidio",
        "labels": [
            "O",
            "B-AGE",
            "I-AGE",
            "B-CREDIT_CARD",
            "I-CREDIT_CARD",
            "B-DATE_TIME",
            "I-DATE_TIME",
            "B-DOMAIN_NAME",
            "I-DOMAIN_NAME",
            "B-EMAIL_ADDRESS",
            "I-EMAIL_ADDRESS",
            "B-GPE",
            "I-GPE",
            "B-IBAN_CODE",
            "I-IBAN_CODE",
            "B-IP_ADDRESS",
            "I-IP_ADDRESS",
            "B-NRP",
            "I-NRP",
            "B-ORGANIZATION",
            "I-ORGANIZATION",
            "B-PERSON",
            "I-PERSON",
            "B-PHONE_NUMBER",
            "I-PHONE_NUMBER",
            "B-STREET_ADDRESS",
            "I-STREET_ADDRESS",
            "B-TITLE",
            "I-TITLE",
            "B-US_DRIVER_LICENSE",
            "I-US_DRIVER_LICENSE",
            "B-US_SSN",
            "I-US_SSN",
            "B-ZIP_CODE",
            "I-ZIP_CODE",
        ],
        "text_col": "tokens",
        "label_col": "labels",
        "split": "test",
    },
}

# Immutable native releases. Keep these in sync with config/registry.go; tests
# compare every entry, including releases outside this classifier evaluator.
VELA_RELEASE_REVISIONS = {
    "llm-semantic-router/Vela-1.0-Encoder-307M": "225bb8021e0e7839e6045b253caadcb19e96bb25",
    "llm-semantic-router/Vela-1.0-Encoder-307M-FactCheck": "e4869536922d693c9213f68ecf7b3c9ff610f3e2",
    "llm-semantic-router/Vela-1.0-Encoder-307M-Domain": "938773f3f7b67392c3aba6f2a344b251de881ecf",
    "llm-semantic-router/Vela-1.0-Encoder-307M-PII": "fe0d5700d4498110fd2a6de71243d95dee4ca657",
    "llm-semantic-router/Vela-1.0-Encoder-307M-Modality": "994b999048f349bfb62fc92578db86ca4e853205",
    "llm-semantic-router/Vela-1.0-Encoder-307M-Feedback": "e7a4f126b4b19810a4dd90ad2019f86acd32e920",
    "llm-semantic-router/Vela-1.0-Encoder-307M-Embedding": "5e639f1a709168f6f1cf69cd519f3aa9221bfbef",
}

MODEL_REGISTRY = deepcopy(LEGACY_MODEL_REGISTRY)
for _role, _suffix in {
    "feedback": "Feedback",
    "fact-check": "FactCheck",
    "intent": "Domain",
    "pii": "PII",
}.items():
    _entry = MODEL_REGISTRY[_role]
    _entry["id"] = f"llm-semantic-router/Vela-1.0-Encoder-307M-{_suffix}"
    _entry["revision"] = VELA_RELEASE_REVISIONS[_entry["id"]]
    # Published lora/ variants require their own reproduction contract. They
    # are not independent *-lora repositories or generic base+adapter loads.
    del _entry["lora_id"]
MODEL_REGISTRY["feedback"]["labels"].append("NO_FEEDBACK")

COLLECTIONS = {"served": MODEL_REGISTRY, "legacy-mom": LEGACY_MODEL_REGISTRY}


def model_registry(collection="served"):
    """Return an explicit collection; never fall back to a legacy artifact."""
    if collection not in COLLECTIONS:
        raise ValueError(f"Unknown model collection: {collection}")
    return COLLECTIONS[collection]
