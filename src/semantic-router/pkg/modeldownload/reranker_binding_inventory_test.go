package modeldownload

import (
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
