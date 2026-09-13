"""Family cycles, complete-text locks and multi-positive retrieval admission."""

import json
import tempfile
import unittest
from pathlib import Path

from src.training.model_embeddings.mmbert_32k.newbase_data import (
    FrozenCorpus,
    GroupCycle,
    file_digest,
    retrieval_masks,
    text_digest,
)


class NewBaseDataTest(unittest.TestCase):
    def test_transitive_parent_overlap_is_one_family(self):
        records = [
            {"id": "a", "parent_groups": ["A", "B"]},
            {"id": "b", "parent_groups": ["B", "C"]},
            {"id": "c", "parent_groups": ["C"]},
            {"id": "d", "parent_groups": ["D"]},
        ]
        left, right = GroupCycle(records, 12), GroupCycle(records, 12)
        self.assertEqual(set(left.groups), {("A", "B", "C"), ("D",)})
        for _ in range(10):
            batch = left.draw(2)
            self.assertEqual(batch, right.draw(2))
            self.assertEqual(sum(row["id"] == "d" for row in batch), 1)
        with self.assertRaisesRegex(ValueError, "distinct"):
            left.draw(3)

    def test_batch_crossing_cycle_boundary_preserves_without_replacement(self):
        records = [{"id": str(i), "parent_groups": [str(i)]} for i in range(5)]
        sampler = GroupCycle(records, 123)
        for _ in range(11):
            batch = sampler.draw(3)
            self.assertEqual(len({row["id"] for row in batch}), 3)
        counts = list(sampler.draw_counts.values())
        self.assertLessEqual(max(counts) - min(counts), 1)

    def test_related_unknowns_masked_but_judged_negatives_preserved(self):
        components = {
            key: {"normalized_sha256": key, "parent_groups": parents}
            for key, parents in {"p": ["A"], "q": ["A"], "n": ["A"], "u": ["B"]}.items()
        }
        rows = [
            {"positive_component_ids": ["p"], "judged_negative_component_ids": ["n"]}
        ]
        positive, valid = retrieval_masks(rows, ["p", "q", "n", "u"], components)
        self.assertEqual(positive, [[True, False, False, False]])
        self.assertEqual(valid, [[True, False, True, True]])
        components["q"]["normalized_sha256"] = "p"
        with self.assertRaisesRegex(ValueError, "Identical"):
            retrieval_masks(rows, ["p", "q"], components)

    def test_wrong_partition_and_modified_corpus_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            components = [
                {
                    "id": key,
                    "text": text,
                    "text_sha256": text_digest(text),
                    "normalized_sha256": text_digest(text, normalize=True),
                    "parent_groups": [key],
                }
                for key, text in (("q", "query"), ("p", "passage"))
            ]
            records = [
                {
                    "id": "r",
                    "source": "miracl",
                    "language": "en",
                    "split": "train",
                    "parent_groups": ["r"],
                    "query_component_id": "q",
                    "positive_component_ids": ["p"],
                    "judged_negative_component_ids": [],
                    "unjudged_component_ids": [],
                }
            ]
            for filename, values in (
                ("components.jsonl", components),
                ("records.jsonl", records),
            ):
                (root / filename).write_text(
                    "".join(json.dumps(row) + "\n" for row in values)
                )
            manifest = {
                "split": "train",
                "files": {
                    file: {"sha256": file_digest(root / file)}
                    for file in ("components.jsonl", "records.jsonl")
                },
            }
            (root / "manifest.json").write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, "partition"):
                FrozenCorpus.load(root, "validation")
            self.assertEqual(len(FrozenCorpus.load(root, "train").records), 1)
            (root / "components.jsonl").write_text("changed")
            with self.assertRaisesRegex(ValueError, "changed"):
                FrozenCorpus.load(root, "train")


if __name__ == "__main__":
    unittest.main()
