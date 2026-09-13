package modeldownload

import (
	"os"
	"path/filepath"
	"slices"
	"testing"

	"github.com/vllm-project/semantic-router/src/semantic-router/pkg/config"
)

func TestRerankerInventoryRequiresEncoderAndSafeHeadsOnlyWhenActive(t *testing.T) {
	cfg := &config.RouterConfig{MoMRegistry: map[string]string{"models/reranker": "test/reranker"}}
	cfg.ModelDeployments = map[string]config.ModelDeployment{"rank": {Provider: "candle", Artifact: "models/reranker"}}
	cfg.ModelBindings = map[string]config.ModelBinding{config.RAGRerankerConsumer: {Deployment: "rank", Contract: config.RelevanceScoresContract, Adapter: "vela_reranker"}}
	cfg.Decisions = []config.Decision{{Name: "retrieve", Plugins: []config.DecisionPlugin{{Type: "rag", Configuration: config.MustStructuredPayload(config.RAGPluginConfig{Enabled: true, Backend: "vectorstore", Rerank: &config.RAGRerankConfig{}})}}}}
	specs, err := BuildModelSpecs(cfg)
	if err != nil {
		t.Fatal(err)
	}
	model, ok := findSpecByPath(specs, "models/reranker")
	if !ok {
		t.Fatalf("active reranker omitted: %+v", specs)
	}
	for _, file := range []string{"config.json", "tokenizer.json", "classification_heads.safetensors", "matryoshka_config.json"} {
		if !slices.Contains(model.RequiredFiles, file) {
			t.Fatalf("missing %s", file)
		}
	}
	if len(model.RequiredFileGroups) != 1 || slices.Contains(model.RequiredFileGroups[0], "*.safetensors") {
		t.Fatal("head file can masquerade as encoder weights")
	}
	cfg.Decisions = nil
	specs, err = BuildModelSpecs(cfg)
	if err != nil {
		t.Fatal(err)
	}
	if _, ok = findSpecByPath(specs, "models/reranker"); ok {
		t.Fatal("unused reranker downloaded")
	}
}

func TestORTRerankerSnapshotRequiresSelectedGraphAndMetadata(t *testing.T) {
	for _, tc := range []struct {
		name      string
		selection *config.PairScorerSelection
		head      string
		graph     string
	}{
		{"full", nil, "", "onnx/model.onnx"},
		{"flat", &config.PairScorerSelection{Layer: 2, Dimension: 4}, "", "onnx/model_layer_2_dim_4.onnx"},
		{"nested", &config.PairScorerSelection{Layer: 2, Dimension: 4}, "", "onnx/layer-2/dim-4/model.onnx"},
		{"explicit head", nil, "selected.onnx", "selected.onnx"},
		{"partial layer", &config.PairScorerSelection{Layer: 2}, "", "onnx/model_layer_2_dim_4.onnx"},
		{"partial dimension", &config.PairScorerSelection{Dimension: 4}, "", "onnx/layer-2/dim-4/model.onnx"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			cfg := &config.RouterConfig{MoMRegistry: map[string]string{dir: "test/reranker"}}
			cfg.ModelDeployments = map[string]config.ModelDeployment{"rank": {Provider: "ort", Artifact: dir}}
			cfg.ModelBindings = map[string]config.ModelBinding{config.RAGRerankerConsumer: {Deployment: "rank", Contract: config.RelevanceScoresContract, Adapter: "vela_reranker", PairScorer: tc.selection, Head: tc.head}}
			cfg.Decisions = []config.Decision{{Name: "retrieve", Plugins: []config.DecisionPlugin{{Type: "rag", Configuration: config.MustStructuredPayload(config.RAGPluginConfig{Enabled: true, Backend: "vectorstore", Rerank: &config.RAGRerankConfig{}})}}}}
			specs, err := BuildModelSpecs(cfg)
			if err != nil {
				t.Fatal(err)
			}
			spec, ok := findSpecByPath(specs, dir)
			if !ok || slices.Contains(spec.RequiredFiles, "classification_heads.safetensors") {
				t.Fatalf("invalid ORT snapshot requirements: %+v", specs)
			}
			for _, name := range []string{"config.json", "tokenizer.json", "matryoshka_config.json"} {
				writeModelFile(t, dir, name, "{}")
			}
			writeModelFile(t, filepath.Join(dir, "onnx"), "model_layer_9_dim_9.onnx", string(protoBytes(7, nil)))
			assertSnapshotComplete(t, spec, false)
			writeModelFile(t, filepath.Join(dir, filepath.Dir(tc.graph)), filepath.Base(tc.graph), string(protoBytes(7, nil)))
			if err := os.Remove(filepath.Join(dir, "matryoshka_config.json")); err != nil {
				t.Fatal(err)
			}
			assertSnapshotComplete(t, spec, false)
			writeModelFile(t, dir, "matryoshka_config.json", "{}")
			assertSnapshotComplete(t, spec, true)
		})
	}
}

func assertSnapshotComplete(t *testing.T, spec ModelSpec, want bool) {
	t.Helper()
	if complete, err := isSpecComplete(spec); err != nil || complete != want {
		t.Fatalf("snapshot complete=%v, want %v: %v (%+v)", complete, want, err, spec)
	}
}
