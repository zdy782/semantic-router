//go:build !windows && cgo && (amd64 || arm64)

package instance

import (
	"path/filepath"
	"strings"
	"testing"
)

func pairFixture() Options {
	return Options{ModelPath: filepath.Join("testdata", "pair_scorer"), ModelFile: "model.onnx", Provider: "cpu", IntraThreads: 1}
}

func TestOwnedPairScorerUsesRealNativePairsAndRawLogits(t *testing.T) {
	options := pairFixture()
	options.MaxInputTokens = 7
	model, err := LoadPairScorer(options, PairScorerSelection{})
	if err != nil {
		t.Fatal(err)
	}
	clone, err := model.Clone()
	if err != nil {
		t.Fatal(err)
	}
	defer clone.Close()
	if err = model.Close(); err != nil {
		t.Fatal(err)
	}
	pairs := []TextPair{{Query: "hello world", Document: "秘密 hello"}, {Query: "world", Document: "秘密"}}
	if _, err = model.ScorePairs(pairs); err == nil {
		t.Fatal("closed owner accepted pair scoring")
	}
	result, err := clone.ScorePairs(pairs)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Scores) != 2 || result.Scores[0] != 15 || result.Scores[1] != 13 || len(result.Inputs) != 2 || result.Inputs[0].OriginalTokens != 7 || result.Inputs[0].ProcessedTokens != 7 || result.Inputs[0].Truncated {
		t.Fatalf("exact pair IDs or raw logits changed: %+v", result)
	}
	if _, err = clone.ScorePairs([]TextPair{{Query: string([]byte{0xff}), Document: "hello"}}); err == nil {
		t.Fatal("invalid UTF-8 was silently replaced by JSON encoding")
	}
	info, err := clone.Info()
	if err != nil {
		t.Fatal(err)
	}
	if info.Task != "pair_scores" || info.PairScorer == nil || *info.PairScorer != (PairScorerSelection{Layer: 2, Dimension: 4}) || info.CompletedInferences != 2 {
		t.Fatalf("wrong actual head/session evidence: %+v", info)
	}
	if _, err = clone.ScorePairs([]TextPair{pairs[0], {Query: "hello world", Document: "秘密 hello world"}}); err == nil {
		t.Fatal("over-budget pair batch was accepted")
	}
	info, err = clone.Info()
	if err != nil {
		t.Fatal(err)
	}
	if info.CompletedInferences != 2 {
		t.Fatal("failed preparation still ran part of the pair batch")
	}
	if invalid, loadErr := LoadPairScorer(options, PairScorerSelection{Layer: 1, Dimension: 4}); loadErr == nil {
		_ = invalid.Close()
		t.Fatal("wrong graph exit accepted")
	}
	options.Overflow = "truncate_right"
	if invalid, loadErr := LoadPairScorer(options, PairScorerSelection{}); loadErr == nil {
		_ = invalid.Close()
		t.Fatal("pair template truncation accepted")
	}
}

func TestOwnedPairScorerProcessesAll32768TokensAndRejects32769(t *testing.T) {
	model, err := LoadPairScorer(pairFixture(), PairScorerSelection{})
	if err != nil {
		t.Fatal(err)
	}
	defer model.Close()
	pair := TextPair{Query: "hello", Document: strings.Repeat("world ", 32764)}
	result, err := model.ScorePairs([]TextPair{pair})
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Scores) != 1 || result.Scores[0] != 65537 || result.Inputs[0].OriginalTokens != 32768 || result.Inputs[0].ProcessedTokens != 32768 || result.Inputs[0].Truncated {
		t.Fatalf("32K pair content was lost: %+v", result)
	}
	pair.Document += "world"
	if _, err = model.ScorePairs([]TextPair{pair}); err == nil {
		t.Fatal("32769-token pair accepted")
	}
}
