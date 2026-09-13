"""External teacher identity, relation geometry and detached batch gradients."""

import copy
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

try:
    import torch
    from safetensors.torch import save_file

    from src.training.model_embeddings.mmbert_32k.newbase_batches import (
        ObjectiveConfig,
        TokenBatch,
        embedding_step,
        reranker_step,
    )
    from src.training.model_embeddings.mmbert_32k.newbase_data import file_digest
    from src.training.model_embeddings.mmbert_32k.newbase_objectives import (
        order_distillation,
        relational_cosine_loss,
    )
    from src.training.model_embeddings.mmbert_32k.newbase_teacher import (
        TeacherCache,
        embedding_teacher_loss,
        identity_digest,
        input_identity,
        record_inputs,
        token_digest,
        validate_teacher_config,
    )
    from src.training.model_embeddings.mmbert_32k.tests import (
        test_newbase_batches as batch_fixtures,
    )
except ImportError:
    torch = None


@unittest.skipIf(torch is None, "requires torch, transformers and safetensors")
class NewBaseTeacherTest(unittest.TestCase):
    def cache(self, path, task, rows, components, embedding_dimensions=16):
        records = [{"id": str(index), **row} for index, row in enumerate(rows)]
        corpus = SimpleNamespace(
            records=records,
            components=components,
            manifest_sha256="corpus-digest",
            manifest={"split": "train"},
        )
        draws = [{"record_ids": [row["id"] for row in records]}]
        inputs = sorted({ids for row in records for ids in record_inputs(row, task)})
        batch = TokenBatch.encode(
            batch_fixtures.CompleteTokenizer(),
            [components[ids[0]]["text"] for ids in inputs],
            (
                [components[ids[1]]["text"] for ids in inputs]
                if task == "reranker"
                else None
            ),
            128,
        )
        entries = []
        for index, (ids, tokens) in enumerate(zip(inputs, batch.rows, strict=True)):
            identity = input_identity(ids, components)
            entries.append(
                {
                    "key": identity_digest(identity),
                    "identity": identity,
                    "value_index": index,
                    "token_sha256": token_digest(tokens, batch.pad_id),
                }
            )
        torch.manual_seed(198)
        values = torch.randn(
            len(entries), embedding_dimensions if task == "embedding" else 1
        )
        if task == "embedding":
            values = torch.nn.functional.normalize(values, dim=-1)
        path.mkdir()
        (path / "entries.jsonl").write_text(
            "".join(json.dumps(row) + "\n" for row in entries)
        )
        save_file({"values": values}, path / "values.safetensors")
        manifest = {
            "complete": True,
            "task": task,
            "train_manifest_sha256": corpus.manifest_sha256,
            "source_split": "train",
            "draws_sha256": "draw-digest",
            "dimensions": values.shape[1],
            "teacher": {
                "repo_id": "synthetic/teacher",
                "revision": "fixed-revision",
                "files": {"model.safetensors": "fixed-weight-digest"},
                "representation": "unit vectors" if task == "embedding" else "CLS",
            },
            "files": {
                name: file_digest(path / name)
                for name in ("entries.jsonl", "values.safetensors")
            },
        }
        (path / "manifest.json").write_text(json.dumps(manifest))
        arguments = {
            "task": task,
            "corpus": corpus,
            "draws": draws,
            "draws_sha256": "draw-digest",
        }
        return arguments, TeacherCache.load(
            path, file_digest(path / "manifest.json"), **arguments
        )

    def test_relations_are_basis_invariant_and_masked_with_detached_teacher(self):
        torch.manual_seed(11)
        student = torch.randn(4, 8, requires_grad=True)
        teacher = torch.randn(4, 8, requires_grad=True)
        valid = ~torch.eye(4, dtype=torch.bool)
        rotation = torch.linalg.qr(torch.randn(8, 8)).Q
        expected = relational_cosine_loss(student, student, teacher, teacher, valid)
        actual = relational_cosine_loss(
            student @ rotation, student @ rotation, teacher, teacher, valid
        )
        torch.testing.assert_close(expected, actual, atol=1e-6, rtol=1e-6)
        expected.backward()
        self.assertIsNone(teacher.grad)
        self.assertGreater(float(student.grad.norm()), 0)
        empty = relational_cosine_loss(
            student, student, teacher, teacher, torch.zeros_like(valid)
        )
        self.assertEqual(float(empty.detach()), 0)

    def test_query_order_is_shift_invariant_and_ignores_padded_scores(self):
        student = torch.tensor([[0.2, 0.8, 0.0], [0.3, -0.2, 0.0]], requires_grad=True)
        teacher = torch.tensor(
            [[1.0, -1.0, 200.0], [0.0, 2.0, -900.0]], requires_grad=True
        )
        valid = torch.tensor([[True, True, False], [True, True, False]])
        original = order_distillation(student, teacher, valid)
        shifted = order_distillation(
            student + torch.tensor([[4.0], [-8.0]]),
            teacher + torch.tensor([[-7.0], [5.0]]),
            valid,
        )
        torch.testing.assert_close(original, shifted, atol=1e-6, rtol=1e-6)
        original.backward()
        self.assertIsNone(teacher.grad)
        self.assertTrue(torch.equal(student.grad[:, 2], torch.zeros(2)))

    def test_related_components_do_not_create_off_diagonal_supervision(self):
        student = torch.eye(2)
        teacher = torch.tensor([[0.0, 1.0], [0.0, 1.0]])
        components = {
            key: {"normalized_sha256": key, "parent_groups": ["same-parent"]}
            for key in ("q", "d")
        }
        # A retrieval relation within the same family is excluded; explicitly
        # paired semantic similarity remains an eligible soft relation.
        self.assertEqual(
            float(
                embedding_teacher_loss(
                    student, teacher, ["q", "d"], components, query_count=1
                )
            ),
            0,
        )
        self.assertEqual(
            float(
                embedding_teacher_loss(
                    student, teacher, ["q", "d"], components, query_count=None
                )
            ),
            1,
        )

    def test_semantic_pairs_keep_distinct_teacher_dimensions_and_finite_checks(self):
        student = torch.tensor([[1.0, 0.0], [0.0, 1.0]], requires_grad=True)
        teacher = torch.tensor([[1.0, 0.0, 0.0], [1.0, 0.0, 0.0]], requires_grad=True)
        components = {
            key: {"normalized_sha256": key, "parent_groups": ["same-parent"]}
            for key in ("a", "b")
        }
        loss = embedding_teacher_loss(
            student, teacher, list(components), components, query_count=None
        )
        self.assertEqual(loss.item(), 1)
        loss.backward()
        self.assertGreater(student.grad.norm().item(), 0)
        self.assertIsNone(teacher.grad)
        for invalid in (teacher[:1], teacher[:, :0], teacher.flatten()):
            with self.assertRaisesRegex(ValueError, "geometry"):
                embedding_teacher_loss(
                    student, invalid, list(components), components, query_count=None
                )
        for query_count in (None, 1):
            invalid = teacher.detach().clone()
            invalid[0, 0] = float("nan")
            with self.assertRaisesRegex(ValueError, "finite"):
                embedding_teacher_loss(
                    student,
                    invalid,
                    list(components),
                    components,
                    query_count=query_count,
                )

    def test_cache_rejects_wrong_membership_tokens_shape_and_file_identity(self):
        rows, components = batch_fixtures.NewBaseBatchesTest().examples()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cache"
            arguments, cache = self.cache(path, "embedding", rows, components)
            cache.validate_tokens(batch_fixtures.CompleteTokenizer(), components, 128)
            with self.assertRaisesRegex(ValueError, "input tokens"):
                cache.validate_tokens(batch_fixtures.CompleteTokenizer(), components, 2)
            digest = file_digest(path / "manifest.json")
            with self.assertRaisesRegex(ValueError, "configured training run"):
                TeacherCache.load(path, "another-digest", **arguments)
            changed = copy.deepcopy(arguments)
            changed["draws"] = [{"record_ids": ["0"]}]
            with self.assertRaisesRegex(ValueError, "input identity"):
                TeacherCache.load(path, digest, **changed)
            batch = TokenBatch(((1, 99, 2),), 0)
            with self.assertRaisesRegex(ValueError, "input tokens"):
                cache.lookup([("q1",)], components, batch, torch.device("cpu"))
            changed = copy.deepcopy(arguments)
            changed["corpus"].components["q1"]["text"] += " changed"
            with self.assertRaisesRegex(ValueError, "input identity"):
                TeacherCache.load(path, digest, **changed)
            save_file({"values": torch.zeros(1, 16)}, path / "values.safetensors")
            with self.assertRaisesRegex(ValueError, "cache file changed"):
                TeacherCache.load(path, digest, **arguments)
            manifest = json.loads((path / "manifest.json").read_bytes())
            manifest["files"]["values.safetensors"] = file_digest(
                path / "values.safetensors"
            )
            (path / "manifest.json").write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, "declared geometry"):
                TeacherCache.load(
                    path, file_digest(path / "manifest.json"), **arguments
                )

    def test_real_all_exit_batches_keep_control_math_and_detach_cached_teacher(self):
        fixture = batch_fixtures.NewBaseBatchesTest()
        rows, components = fixture.examples()
        rows[0]["judged_negative_component_ids"] = []
        rows[0]["unjudged_component_ids"] = ["n"]
        original_rows = copy.deepcopy(rows)
        for task, function, kind in (
            ("embedding", embedding_step, "retrieval"),
            ("reranker", reranker_step, "ranking"),
        ):
            with self.subTest(task=task), tempfile.TemporaryDirectory() as directory:
                _, cache = self.cache(
                    Path(directory) / "cache",
                    task,
                    rows,
                    components,
                    embedding_dimensions=24,
                )
                model = fixture.model(task)
                cache.values.requires_grad_(True)
                options = {
                    "device": torch.device("cpu"),
                    "token_budget": 128,
                    "maximum": 128,
                    "objective": ObjectiveConfig(kind),
                    "amp": False,
                }
                baseline, baseline_receipt = function(
                    model,
                    batch_fixtures.CompleteTokenizer(),
                    rows,
                    components,
                    **options,
                )
                zero, zero_receipt = function(
                    model,
                    batch_fixtures.CompleteTokenizer(),
                    rows,
                    components,
                    teacher_cache=cache,
                    teacher_weight=0.0,
                    **options,
                )
                torch.testing.assert_close(zero, baseline, atol=0, rtol=0)
                self.assertEqual(zero_receipt, baseline_receipt)
                treatment, receipt = function(
                    model,
                    batch_fixtures.CompleteTokenizer(),
                    rows,
                    components,
                    teacher_cache=cache,
                    teacher_weight=0.25,
                    **options,
                )
                torch.testing.assert_close(
                    treatment.detach() - baseline.detach(),
                    torch.tensor(0.25 * receipt["external_teacher_loss"]),
                    atol=1e-6,
                    rtol=1e-5,
                )
                treatment.backward()
                self.assertIsNone(cache.values.grad)
                self.assertTrue(all(p.grad is not None for p in model.parameters()))
                self.assertEqual(rows, original_rows)

    def test_explicit_task_cache_configuration(self):
        validate_teacher_config({"objective": "query_order", "weight": 0}, "reranker")
        for config in (
            {"objective": "query_order", "weight": 0.1},
            {"objective": "query_order", "weight": -1},
            {"objective": "relational_cosine", "weight": 0},
        ):
            with self.assertRaises(ValueError):
                validate_teacher_config(config, "reranker")


if __name__ == "__main__":
    unittest.main()
