"""Absolute coordinates cannot be preserved by pairwise relations alone."""

import unittest

try:
    import torch

    from src.training.model_embeddings.mmbert_32k.newbase_semantic import (
        full_batch_relation_loss,
        pointwise_cosine_loss,
    )
except ImportError:
    torch = None


@unittest.skipIf(torch is None, "requires torch")
class SemanticAnchorTest(unittest.TestCase):
    def test_rotation_preserves_relations_but_anchor_restores_coordinates(self):
        teacher = torch.eye(3, requires_grad=True)
        student = teacher.detach().roll(1, dims=1).requires_grad_()
        ids = ["one", "two", "three"]
        components = {
            key: {"normalized_sha256": key, "parent_groups": [key]} for key in ids
        }
        relation = full_batch_relation_loss(student, teacher, ids, components)
        torch.testing.assert_close(relation, torch.tensor(0.0))
        anchor = pointwise_cosine_loss(student, teacher)
        torch.testing.assert_close(anchor, torch.tensor(1.0))
        anchor.backward()
        self.assertGreater(float(student.grad.abs().sum()), 0)
        self.assertIsNone(teacher.grad)
        self.assertLess(
            float(pointwise_cosine_loss(student - student.grad, teacher)), 1
        )

    def test_scale_invariance_and_no_hidden_width_division(self):
        student = torch.tensor([[1.0, 0.0, 0.0, 0.0]])
        teacher = torch.tensor([[0.0, 9.0, 0.0, 0.0]])
        torch.testing.assert_close(
            pointwise_cosine_loss(student, teacher), torch.tensor(1.0)
        )
        torch.testing.assert_close(
            pointwise_cosine_loss(student * 7, teacher * 3), torch.tensor(1.0)
        )
        for bad in (torch.zeros_like(teacher), teacher * float("nan"), teacher[:, :2]):
            with self.subTest(shape=bad.shape), self.assertRaises(ValueError):
                pointwise_cosine_loss(student, bad)

    def test_stronger_teacher_may_have_different_relation_width(self):
        torch.manual_seed(7)
        student = torch.randn(5, 3, requires_grad=True)
        teacher = torch.randn(5, 8, requires_grad=True)
        ids = list("abcde")
        components = {
            key: {"normalized_sha256": key, "parent_groups": [key]} for key in ids
        }
        loss = full_batch_relation_loss(student, teacher, ids, components)
        loss.backward()
        self.assertGreater(float(student.grad.abs().sum()), 0)
        self.assertIsNone(teacher.grad)


if __name__ == "__main__":
    unittest.main()
