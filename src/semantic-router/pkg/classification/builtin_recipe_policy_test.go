package classification

import (
	"errors"
	"os"
	"path/filepath"
	"sync"
	"testing"

	"github.com/vllm-project/semantic-router/src/semantic-router/pkg/config"
	"github.com/vllm-project/semantic-router/src/semantic-router/pkg/decision"
)

func builtinPolicyClassifier(t *testing.T, name string) *Classifier {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("..", "..", "..", "..", "config", "recipes", "built-in", "latest", "mom-v1", "config.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	cfg, err := config.ParseYAMLBytes(data)
	if err != nil {
		t.Fatal(err)
	}
	recipe, ok := cfg.RecipeByName(config.RecipeName(name))
	if !ok {
		t.Fatalf("built-in recipe %q is missing", name)
	}
	return &Classifier{Config: cfg.ConfigForRecipe(recipe)}
}

// These are policy counterexamples, not classifier accuracy measurements. Read
// the shipped recipe and run its actual projections and decision evaluator.
func TestBuiltinBalanceIntentAndRecovery(t *testing.T) {
	c := builtinPolicyClassifier(t, "balance")
	tests := []struct {
		name string
		in   SignalResults
		want string
	}{
		{"uncertain task keeps middle pool", SignalResults{}, "medium"},
		{"positive simple evidence", SignalResults{MatchedComplexityRules: []string{"difficulty:easy"}}, "simple"},
		{"hard task", SignalResults{MatchedComplexityRules: []string{"difficulty:hard"}}, "reasoning"},
		{"reasoning opt out", SignalResults{MatchedComplexityRules: []string{"difficulty:hard"}, MatchedKeywordRules: []string{"deliberate", "no_analysis"}}, "medium"},
		{"quoted execution vocabulary", SignalResults{MatchedKeywordRules: []string{"deliberate", "verify"}, MatchedStructureRules: []string{"quoted_request"}}, "medium"},
		{"topic is not difficulty", SignalResults{MatchedComplexityRules: []string{"difficulty:easy"}, MatchedDomainRules: []string{"health"}, MatchedFactCheckRules: []string{"needs_fact_check"}}, "simple"},
		{"consequential advice combines evidence", SignalResults{MatchedComplexityRules: []string{"difficulty:easy"}, MatchedDomainRules: []string{"health"}, MatchedFactCheckRules: []string{"needs_fact_check"}, MatchedEmbeddingRules: []string{"consequential"}}, "reasoning"},
		{"financial stakes include economics", SignalResults{MatchedDomainRules: []string{"economics"}, MatchedFactCheckRules: []string{"needs_fact_check"}, MatchedEmbeddingRules: []string{"consequential"}}, "reasoning"},
		{"repeat alone is not a failed answer", SignalResults{MatchedConversationRules: []string{"has_answer"}, MatchedReaskRules: []string{"repeat"}}, "medium"},
		{"negative feedback after answer", SignalResults{MatchedConversationRules: []string{"has_answer"}, MatchedUserFeedbackRules: []string{"wrong_answer"}}, "reasoning"},
		{"explicit correction without transmitted history", SignalResults{MatchedKeywordRules: []string{"correction"}, MatchedUserFeedbackRules: []string{"wrong_answer"}}, "reasoning"},
		{"repeat with correction", SignalResults{MatchedConversationRules: []string{"has_answer"}, MatchedReaskRules: []string{"repeat"}, MatchedKeywordRules: []string{"correction"}}, "reasoning"},
		{"quoted feedback is not recovery", SignalResults{MatchedConversationRules: []string{"has_answer"}, MatchedUserFeedbackRules: []string{"wrong_answer"}, MatchedStructureRules: []string{"quoted_request"}}, "medium"},
		{"classifier error does not fabricate low complexity", builtinComplexityUnavailable(c, SignalResults{}), "medium"},
		{"failed feedback propagates through projection", SignalResults{MatchedConversationRules: []string{"has_answer"}, MatchedReaskRules: []string{"repeat"}, MatchedKeywordRules: []string{"correction"}, SignalErrors: map[string]string{"user_feedback:wrong_answer": "unavailable"}}, "medium"},
		{"active tool conversation is not simple", SignalResults{MatchedComplexityRules: []string{"difficulty:easy"}, MatchedConversationRules: []string{"tool_loop"}}, "medium"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) { assertBuiltinPolicy(t, c, &tt.in, tt.want) })
	}
}

func TestBuiltinSpeedAndCostToolIntent(t *testing.T) {
	for _, profile := range []struct{ name, fallback string }{{"speed", "fast"}, {"cost", "economy"}} {
		t.Run(profile.name, func(t *testing.T) {
			c := builtinPolicyClassifier(t, profile.name)
			for _, tt := range []struct {
				name string
				in   SignalResults
				want string
			}{
				{"tools merely available", SignalResults{MatchedConversationRules: []string{"has_tools"}}, profile.fallback},
				{"explicit execution with definitions", SignalResults{MatchedConversationRules: []string{"has_tools"}, MatchedKeywordRules: []string{"tool_intent"}}, "tools"},
				{"tool intent without definitions", SignalResults{MatchedKeywordRules: []string{"tool_intent"}}, profile.fallback},
				{"required named tool", SignalResults{MatchedConversationRules: []string{"has_tools", "tool_required"}}, "tools"},
				{"tools disabled", SignalResults{MatchedConversationRules: []string{"has_tools", "tool_disabled"}, MatchedKeywordRules: []string{"tool_intent"}}, profile.fallback},
				{"quoted tool action", SignalResults{MatchedConversationRules: []string{"has_tools"}, MatchedKeywordRules: []string{"tool_intent"}, MatchedStructureRules: []string{"quoted_request"}}, profile.fallback},
				{"quoted correction is not answer recovery", SignalResults{MatchedConversationRules: []string{"has_answer"}, MatchedReaskRules: []string{"repeat"}, MatchedKeywordRules: []string{"correction"}, MatchedStructureRules: []string{"quoted_request"}}, profile.fallback},
				{"continue actual tool loop", SignalResults{MatchedConversationRules: []string{"tool_loop"}, MatchedComplexityRules: []string{"difficulty:hard"}}, "tools"},
				{"unknown difficulty preserves quality", builtinComplexityUnavailable(c, SignalResults{}), "reasoning"},
				{"explicit no analysis overrides unknown difficulty", builtinComplexityUnavailable(c, SignalResults{MatchedKeywordRules: []string{"no_analysis"}}), profile.fallback},
			} {
				t.Run(tt.name, func(t *testing.T) { assertBuiltinPolicy(t, c, &tt.in, tt.want) })
			}
		})
	}
}

func TestBuiltinAccuracyRequiresExecutionIntent(t *testing.T) {
	c := builtinPolicyClassifier(t, "accuracy")
	for _, tt := range []struct {
		name string
		in   SignalResults
		want string
	}{
		{"strong single default", SignalResults{}, "simple"},
		{"hard does not imply fanout", SignalResults{MatchedComplexityRules: []string{"difficulty:hard"}}, "reasoning"},
		{"review keyword alone", SignalResults{MatchedKeywordRules: []string{"review"}}, "simple"},
		{"review semantics alone", SignalResults{MatchedEmbeddingRules: []string{"review_intent"}}, "simple"},
		{"explicit independent review", SignalResults{MatchedKeywordRules: []string{"review"}, MatchedEmbeddingRules: []string{"review_intent"}}, "review"},
		{"single model vetoes review", SignalResults{MatchedKeywordRules: []string{"review", "single"}, MatchedEmbeddingRules: []string{"review_intent"}}, "simple"},
		{"quoted workflow does not execute", SignalResults{MatchedKeywordRules: []string{"workflow"}, MatchedEmbeddingRules: []string{"workflow_intent"}, MatchedStructureRules: []string{"quoted_request"}}, "simple"},
		{"explicit workflow", SignalResults{MatchedKeywordRules: []string{"workflow"}, MatchedEmbeddingRules: []string{"workflow_intent"}}, "agent"},
		{"client tool loop stays single", SignalResults{MatchedKeywordRules: []string{"workflow", "review"}, MatchedEmbeddingRules: []string{"workflow_intent", "review_intent"}, MatchedConversationRules: []string{"tool_loop"}}, "reasoning"},
		{"Router flow state resumes", SignalResults{MatchedConversationRules: []string{"flow", "tool_loop"}}, "agent"},
		{"workflow semantics unavailable does not fanout", SignalResults{MatchedKeywordRules: []string{"workflow"}, SignalErrors: map[string]string{"embedding:workflow_intent": "unavailable"}}, "simple"},
		{"unknown difficulty stays strong single", builtinComplexityUnavailable(c, SignalResults{}), "reasoning"},
	} {
		t.Run(tt.name, func(t *testing.T) { assertBuiltinPolicy(t, c, &tt.in, tt.want) })
	}
}

func TestBuiltinVaultUnknownTriageFailsClosed(t *testing.T) {
	c := builtinPolicyClassifier(t, "vault")
	for _, tt := range []struct {
		name string
		in   SignalResults
		want string
	}{
		{"ordinary private request", SignalResults{}, "private"},
		{"personal data", SignalResults{MatchedPIIRules: []string{"personal_data"}}, "sensitive"},
		{"explicit confidential request", SignalResults{MatchedKeywordRules: []string{"confidential"}}, "sensitive"},
		{"security outranks sensitivity", SignalResults{MatchedPIIRules: []string{"personal_data"}, MatchedJailbreakRules: []string{"prompt_attack"}}, "guard"},
		{"unsafe content receives responsible handling", SignalResults{MatchedSafetyRules: []string{"unsafe"}}, "sensitive"},
		{"unavailable Guard", SignalResults{SignalErrors: map[string]string{"jailbreak:prompt_attack": "unavailable"}}, ""},
		{"unavailable Safety", SignalResults{SignalErrors: map[string]string{"safety:unsafe": "unavailable"}}, ""},
		{"unavailable PII", SignalResults{SignalErrors: map[string]string{"pii:personal_data": "unavailable"}}, ""},
		{"content risk cannot resolve an unknown prompt attack", SignalResults{MatchedSafetyRules: []string{"unsafe"}, SignalErrors: map[string]string{"jailbreak:prompt_attack": "unavailable"}}, ""},
		{"hazard can identify care when binary safety is negative", SignalResults{MatchedClassifierRules: []string{"content-risk:self_harm"}}, "sensitive"},
		{"hazard failure is not evidence for ordinary handling", SignalResults{SignalErrors: map[string]string{"classifier:content-risk": "unavailable"}}, ""},
	} {
		t.Run(tt.name, func(t *testing.T) { assertBuiltinPolicy(t, c, &tt.in, tt.want) })
	}
}

func TestBuiltinVaultPrivacyIsIndependentOfVerdict(t *testing.T) {
	cfg := builtinPolicyClassifier(t, "vault").Config
	if cfg.DataPolicy.ReplayAllowed() {
		t.Fatal("Vault must deny replay before any decision is selected")
	}
	for _, route := range cfg.Decisions {
		t.Run(route.Name, func(t *testing.T) {
			tools := route.GetToolsConfig()
			memory := route.GetMemoryConfig()
			cache := route.GetResponseCacheConfig()
			if tools == nil || !tools.Enabled || tools.EffectiveMode() != config.ToolsPluginModeNone || !tools.StripToolHistory {
				t.Fatal("every Vault verdict must prevent client tool dispatch")
			}
			if memory == nil || memory.Enabled || cache == nil || cache.Enabled {
				t.Fatal("every Vault verdict must disable memory and response caching")
			}
			drop := false
			for _, emit := range route.Emits {
				if emit.Kind == "retention" && emit.Retention != nil && emit.Retention.Drop != nil && *emit.Retention.Drop {
					drop = true
				}
			}
			if !drop || route.Adaptations.EffectiveMode() != config.DecisionAdaptationModeBypass {
				t.Fatal("every Vault verdict must suppress content writes and adaptation")
			}
		})
	}
}

func assertBuiltinPolicy(t *testing.T, c *Classifier, input *SignalResults, want string) {
	t.Helper()
	result, err := c.EvaluateDecisionWithEngine(c.applyProjections(input))
	if want == "" {
		if result != nil || !errors.Is(err, decision.ErrDecisionUnresolved) {
			t.Fatalf("wanted unresolved policy, got result=%+v err=%v", result, err)
		}
		return
	}
	if err != nil || result == nil || result.Decision == nil || result.Decision.Name != want {
		t.Fatalf("wanted %q, got result=%+v err=%v", want, result, err)
	}
}

func builtinComplexityUnavailable(c *Classifier, input SignalResults) SignalResults {
	var mu sync.Mutex
	c.recordComplexityFailure(&input, &mu)
	return input
}
